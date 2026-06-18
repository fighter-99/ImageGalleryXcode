#!/usr/bin/env python3
"""
ImageGallery bug pattern scanner.

扫描 Swift 源码, 检测常见 bug pattern, 输出 markdown 报告.

设计原则:
  - 高 signal-to-noise: 过滤掉 Swift boilerplate (init?(coder:)) + 注释 + doc comment
  - 分级: HIGH (几乎肯定 bug) / MED (可能 bug) / LOW (smell)
  - 默认排除测试目录 (ImageGalleryTests/) - 测试代码允许更多 try! / print
  - 默认排除 build 产物 (DerivedData, .build, build/, .git/)

Usage:
  ./bug-scan.py                      # 全扫, markdown to stdout
  ./bug-scan.py --json               # JSON 格式 (for CI)
  ./bug-scan.py --include-tests      # 也扫测试代码
  ./bug-scan.py --baseline           # 写报告到 docs/bug-scan-baseline.md
  ./bug-scan.py --check              # HIGH > 0 则 exit 1 (for CI gate)
  ./bug-scan.py PATH                 # 只扫指定子目录

V6.22.4 (Layer 1 静态扫描): 首个 bug-scan 脚本, 覆盖 V6.20 audit 17 bug pattern + V6.22.3 后新增.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent
PROD_DIR = REPO_ROOT / "ImageGallery"
TEST_DIR = REPO_ROOT / "ImageGalleryTests"

EXCLUDE_DIRS = {
    ".git",
    "build",
    ".build",
    "DerivedData",
    ".swiftpm",
    "node_modules",
    "ImageGallery.xcodeproj",  # pbxproj 内部
    "ImageGallery.xcworkspace",
}

# Swift boilerplate 白名单: 这些 pattern 即使命中也不算 bug
NSCODING_FATAL_PATTERN = re.compile(
    r"required\s+init\?\s*\(\s*coder:\s*NSCoder\s*\)\s*\{[^}]*fatalError",
    re.MULTILINE | re.DOTALL,
)
# 文档注释 (/// 或 //) 标记一行是注释
COMMENT_LINE_PATTERN = re.compile(r"^\s*(///|//|\*)")
# 跨行 /* ... */ 块注释 (粗略判断, 不追求 100% 精确)
BLOCK_COMMENT_START = "/*"

# ---------------------------------------------------------------------------
# Pattern 定义
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Pattern:
    """单个 bug pattern 定义."""

    id: str
    severity: str  # HIGH / MED / LOW
    title: str
    regex: re.Pattern
    rationale: str
    allow_in_comment: bool = False  # 注释里是否允许 (默认 False)
    allow_nscoding: bool = False  # NSCoding 模板是否允许
    exclude_paths: tuple[str, ...] = ()  # 路径子串排除 (如 "ImageImporter.swift")

    def matches(self, line: str, is_comment: bool) -> bool:
        if is_comment and not self.allow_in_comment:
            return False
        return bool(self.regex.search(line))


PATTERNS: list[Pattern] = [
    # ---- HIGH: 几乎肯定 bug ----
    Pattern(
        id="force_try_runtime",
        severity="HIGH",
        title="Force try 运行时调用",
        # try! 后跟的不是字符串字面量 (排除 literal regex)
        regex=re.compile(r"\btry!\b(?!\s*NSRegularExpression)"),
        rationale=(
            "try! 会在错误时崩溃,除非调用的是 literal NSRegularExpression 等"
            "已知安全 pattern。生产代码用 do/catch + 错误处理。"
        ),
    ),
    Pattern(
        id="force_cast_as_bang",
        severity="HIGH",
        title="Force cast (as!)",
        regex=re.compile(r"\bas!\s"),
        rationale="类型不匹配时崩溃, 应用 as? + 处理 nil。",
    ),
    Pattern(
        id="fatal_error_prod",
        severity="HIGH",
        title="Production fatalError",
        # init?(coder:) { fatalError() } 是 Swift 模板, 跳过
        regex=re.compile(r"\bfatalError\s*\("),
        rationale=(
            "生产代码应避免 fatalError (用户崩溃无解)。"
            "init?(coder:) 是 NSCoding 模板例外。"
        ),
        allow_nscoding=True,
    ),
    Pattern(
        id="debug_print",
        severity="HIGH",
        title="Debug print 残留",
        regex=re.compile(r"^\s*print\s*\("),
        rationale=(
            "生产代码用 os.Logger / Logger。"
            "print 会污染 stdout, 影响用户和 CI 抓取。"
        ),
    ),
    # ---- MED: 通常 bug, 偶尔有意 ----
    Pattern(
        id="empty_catch",
        severity="MED",
        title="空 catch (静默吞错)",
        # catch 后立即换行或 }
        regex=re.compile(r"\}\s*catch\s*(?:\{[^}]{0,200}\}|\s*$)"),
        rationale="空 catch 吞掉所有错误, 调试噩梦。至少应 os_log。",
    ),
    Pattern(
        id="silent_try_question",
        severity="MED",
        title="try? 显式丢弃",
        # 只匹配最明确的问题: let _ = try? (显式丢弃返回值 + 错误)
        # 其他 try? 配合 ?? / guard let / if let 都是合法 fallback, 不报
        regex=re.compile(r"\blet\s+_\s*=\s*try\?\s"),
        rationale=(
            "`let _ = try?` 同时丢弃值和错误, 完全静默吞错。"
            "其他 try? 配合 ?? / guard let / if let 都是合法 fallback。"
        ),
    ),
    Pattern(
        id="todo_comment",
        severity="MED",
        title="TODO 注释",
        regex=re.compile(r"^\s*///?\s*(?:TODO|FIXME|XXX|HACK)\b"),
        rationale=(
            "未完成标记。V6.20 audit 阶段通常会清理,"
            "V6.22.4+ 应保持 0 TODO。"
        ),
        allow_in_comment=True,  # 注释里允许出现 (本身是注释)
    ),
    # ---- LOW: smell, 不一定 bug ----
    Pattern(
        id="force_unwrap_bang",
        severity="LOW",
        title="Implicit force unwrap (!)",
        # 排除关键字 (try / as / self / if / guard / return / while / for / case) 后的 !
        # try! / as! 由专门 pattern 覆盖, 这里只抓真正的 implicit force unwrap
        regex=re.compile(
            r"\b(?!try\b|as\b|self\b|if\b|guard\b|return\b|while\b|for\b|case\b)"
            r"([a-zA-Z_][a-zA-Z0-9_]*|\))"
            r"\!(?=[\.,\)\;\n\s])"
        ),
        rationale=(
            "force unwrap。允许场景: @State var x: T = ... 初始,"
            "let y = foo.bar!.baz 等已知安全路径。"
            "try! / as! 由专门 pattern 覆盖, 这里排除以免双计。"
        ),
    ),
]


# ---------------------------------------------------------------------------
# 扫描逻辑
# ---------------------------------------------------------------------------


@dataclass
class Finding:
    file: Path
    line: int
    column: int
    pattern_id: str
    severity: str
    title: str
    snippet: str  # 那一行内容
    rationale: str

    def to_dict(self) -> dict:
        return {
            "file": str(self.file.relative_to(REPO_ROOT)),
            "line": self.line,
            "column": self.column,
            "pattern_id": self.pattern_id,
            "severity": self.severity,
            "title": self.title,
            "snippet": self.snippet.strip(),
            "rationale": self.rationale,
        }


def is_comment_line(line: str) -> bool:
    """判断是否是注释行 (单行 // 或块注释 /* */ 内)."""
    stripped = line.strip()
    if stripped.startswith("//") or stripped.startswith("*"):
        return True
    return False


def file_uses_nscoding(content: str) -> bool:
    """文件是否使用了 NSCoding 模板 (跳过 init?(coder:) { fatalError() })."""
    return bool(NSCODING_FATAL_PATTERN.search(content))


def should_exclude(file_path: Path, include_tests: bool = False) -> bool:
    """是否排除此文件 (build 产物 / 测试)."""
    rel = file_path.relative_to(REPO_ROOT)
    parts = set(rel.parts)
    if parts & EXCLUDE_DIRS:
        return True
    if "ImageGalleryTests" in parts and not include_tests:
        return True
    return False


def scan_file(file_path: Path, patterns: list[Pattern]) -> list[Finding]:
    """扫描单个文件, 返回 findings."""
    findings: list[Finding] = []
    try:
        content = file_path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return findings

    has_nscoding = any(p.allow_nscoding for p in patterns) and file_uses_nscoding(content)

    in_block_comment = False
    for i, line in enumerate(content.splitlines(), 1):
        # 块注释追踪 (粗略)
        if "/*" in line and "*/" not in line:
            in_block_comment = True
        if "*/" in line and "/*" not in line:
            in_block_comment = False

        is_comment = in_block_comment or is_comment_line(line)
        col = line.find(line.strip())  # 缩进列数

        for pat in patterns:
            # 路径排除
            if any(ex in str(file_path) for ex in pat.exclude_paths):
                continue
            # NSCoding 模板白名单 (整个文件级, 不再单行判断)
            if has_nscoding and pat.id == "fatal_error_prod":
                continue

            if pat.matches(line, is_comment):
                findings.append(
                    Finding(
                        file=file_path,
                        line=i,
                        column=col + 1,
                        pattern_id=pat.id,
                        severity=pat.severity,
                        title=pat.title,
                        snippet=line.rstrip(),
                        rationale=pat.rationale,
                    )
                )

    return findings


def iter_swift_files(root: Path, subdir: Path | None = None) -> Iterable[Path]:
    """迭代 swift 文件, 应用排除规则."""
    base = subdir if subdir else root
    for path in sorted(base.rglob("*.swift")):
        if not should_exclude(path):
            yield path


def scan(target: Path | None = None, include_tests: bool = False) -> list[Finding]:
    """主扫描函数."""
    target = target or PROD_DIR
    all_findings: list[Finding] = []
    for path in sorted(target.rglob("*.swift")):
        if should_exclude(path, include_tests=include_tests):
            continue
        all_findings.extend(scan_file(path, PATTERNS))
    return all_findings


# ---------------------------------------------------------------------------
# 报告输出
# ---------------------------------------------------------------------------


SEVERITY_ORDER = {"HIGH": 0, "MED": 1, "LOW": 2}


def render_markdown(findings: list[Finding]) -> str:
    """渲染 markdown 报告."""
    by_sev: dict[str, list[Finding]] = {"HIGH": [], "MED": [], "LOW": []}
    for f in findings:
        by_sev[f.severity].append(f)

    lines: list[str] = []
    lines.append("# ImageGallery Bug Pattern Scan Report")
    lines.append("")
    lines.append(f"扫描路径: `ImageGallery/` (生产代码)")
    lines.append(f"总 findings: **{len(findings)}** "
                 f"(HIGH {len(by_sev['HIGH'])} / "
                 f"MED {len(by_sev['MED'])} / "
                 f"LOW {len(by_sev['LOW'])})")
    lines.append("")

    if not findings:
        lines.append("✅ **0 findings** — 代码干净。")
        return "\n".join(lines)

    # 按 severity 分组
    for sev in ("HIGH", "MED", "LOW"):
        items = by_sev[sev]
        if not items:
            continue
        lines.append(f"## {sev} ({len(items)})")
        lines.append("")
        # 按 pattern_id 分组
        by_pid: dict[str, list[Finding]] = {}
        for f in items:
            by_pid.setdefault(f.pattern_id, []).append(f)
        for pid, fs in sorted(by_pid.items()):
            first = fs[0]
            lines.append(f"### `{pid}` — {first.title} ({len(fs)})")
            lines.append(f"_{first.rationale}_")
            lines.append("")
            lines.append("| File | Line | Snippet |")
            lines.append("|------|------|---------|")
            for f in fs[:20]:  # 每 pattern 最多列 20 行
                rel = f.file.relative_to(REPO_ROOT)
                snippet = f.snippet.replace("|", "\\|")[:100]
                lines.append(f"| `{rel}` | {f.line} | `{snippet}` |")
            if len(fs) > 20:
                lines.append(f"| ... | ... | _{len(fs) - 20} more, 详见 `--json`_ |")
            lines.append("")

    return "\n".join(lines)


def render_summary(findings: list[Finding]) -> str:
    """控制台简短摘要."""
    by_sev = {"HIGH": 0, "MED": 0, "LOW": 0}
    for f in findings:
        by_sev[f.severity] += 1
    return (
        f"扫描完成: {len(findings)} findings "
        f"(HIGH {by_sev['HIGH']} / MED {by_sev['MED']} / LOW {by_sev['LOW']})"
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description="ImageGallery bug pattern scanner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "path",
        nargs="?",
        default=None,
        help="扫描子目录 (默认 ImageGallery/)",
    )
    parser.add_argument(
        "--include-tests",
        action="store_true",
        help="也扫描 ImageGalleryTests/",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="输出 JSON 格式 (for CI)",
    )
    parser.add_argument(
        "--baseline",
        action="store_true",
        help="写报告到 docs/bug-scan-baseline.md",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="HIGH > 0 时 exit 1 (CI gate)",
    )
    parser.add_argument(
        "--show-rationale",
        action="store_true",
        help="每条 finding 显示 rationale",
    )
    args = parser.parse_args()

    target = Path(args.path).resolve() if args.path else PROD_DIR
    if not target.exists():
        print(f"❌ 路径不存在: {target}", file=sys.stderr)
        return 2

    findings = scan(target, include_tests=args.include_tests)
    findings.sort(key=lambda f: (SEVERITY_ORDER[f.severity], f.file.name, f.line))

    if args.json:
        # JSON 模式只输出 JSON (不能有 summary 污染)
        print(json.dumps([f.to_dict() for f in findings], indent=2, ensure_ascii=False))
        return 0
    elif args.baseline:
        out = REPO_ROOT / "docs" / "bug-scan-baseline.md"
        out.parent.mkdir(exist_ok=True)
        out.write_text(render_markdown(findings), encoding="utf-8")
        print(f"✅ Baseline 报告已写: {out.relative_to(REPO_ROOT)}")
    else:
        print(render_markdown(findings))
        if args.show_rationale:
            print("\n--- rationale (已合并在每个 pattern header) ---")

    print()
    print(render_summary(findings))

    if args.check:
        high_count = sum(1 for f in findings if f.severity == "HIGH")
        if high_count > 0:
            print(f"\n❌ CI gate fail: {high_count} HIGH findings", file=sys.stderr)
            return 1
        print("\n✅ CI gate pass: 0 HIGH findings")
    return 0


if __name__ == "__main__":
    sys.exit(main())