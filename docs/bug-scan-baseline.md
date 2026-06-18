# ImageGallery Bug Pattern Scan Report

扫描路径: `ImageGallery/` (生产代码)
总 findings: **11** (HIGH 9 / MED 2 / LOW 0)

## HIGH (9)

### `debug_print` — Debug print 残留 (8)
_生产代码用 os.Logger / Logger。print 会污染 stdout, 影响用户和 CI 抓取。_

| File | Line | Snippet |
|------|------|---------|
| `ImageGallery/ImageImporter.swift` | 193 | `        print("📥 importURLs 收到 \(urls.count) 个 URL")` |
| `ImageGallery/ImageImporter.swift` | 195 | `            print("   - \(url.path)")` |
| `ImageGallery/ImageImporter.swift` | 204 | `        print("📂 展开后共 \(allFiles.count) 个文件")` |
| `ImageGallery/ImageImporter.swift` | 206 | `            print("   [\(i+1)/\(allFiles.count)] \(file.lastPathComponent)")` |
| `ImageGallery/ImageImporter.swift` | 270 | `            print("⏭️ 跳过不支持的格式: \(url.lastPathComponent)")` |
| `ImageGallery/ImageImporter.swift` | 280 | `            print("❌ 复制失败: \(url.lastPathComponent) - \(error.localizedDescription)")` |
| `ImageGallery/ImageImporter.swift` | 307 | `            print("✅ 已导入: \(url.lastPathComponent)")` |
| `ImageGallery/ImageImporter.swift` | 310 | `            print("❌ 保存失败: \(error.localizedDescription)")` |

### `fatal_error_prod` — Production fatalError (1)
_生产代码应避免 fatalError (用户崩溃无解)。init?(coder:) 是 NSCoding 模板例外。_

| File | Line | Snippet |
|------|------|---------|
| `ImageGallery/ImageGalleryApp.swift` | 162 | `                fatalError("ModelContainer 重置后仍失败: \(String(describing: error))")` |

## MED (2)

### `empty_catch` — 空 catch (静默吞错) (2)
_空 catch 吞掉所有错误, 调试噩梦。至少应 os_log。_

| File | Line | Snippet |
|------|------|---------|
| `ImageGallery/Models/ContentViewModel.swift` | 1173 | `                } catch { errors += 1 }` |
| `ImageGallery/Models/ContentViewModel.swift` | 1192 | `                } catch { undoErrors += 1 }` |
