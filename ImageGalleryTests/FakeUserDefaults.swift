//
//  FakeUserDefaults.swift
//  ImageGalleryTests
//
//  V6.12.21: in-memory UserDefaults mock — 完全避开 cfprefsd 守护进程
//
//  根因: UserDefaults(suiteName:) 走 cfprefsd 进程, 并行下 trap
//    (memory: swift-testing-userdefaults-parallel-crash)
//  解决: 继承 UserDefaults, override 全部 read/write, init 只注册 1 个 stub suite (cfprefsd 1 次注册)
//    后续 set/get 走 self.storage, 完全不碰 cfprefsd
//
//  API 覆盖范围: UserSettings 用的 7 个方法 (set/object/string/bool/double/integer/removeObject)
//    不覆盖 array/dictionary/data — UserSettings 不用, 加了反而引入测试盲区
//

import Foundation

/// V6.12.21: in-memory UserDefaults — 100% 测试隔离, 0 cfprefsd 交互
///
/// 跟 UserSettings 完美兼容——`UserSettings(defaults: FakeUserDefaults())` 直接工作
final class FakeUserDefaults: UserDefaults {
    /// V6.12.21: in-memory storage, lock 保护 Swift Testing 并行下读写
    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    /// V6.12.21: super init 用 stub name, cfprefsd 只注册 1 次, 之后所有读写走 storage
    init() {
        // 用唯一 stub name 让 cfprefsd 知道这是"假" suite, 不持久化
        //   整个 test process 共享 1 个 stub (init 1 次) — 比 V6.12.20 共享 suite 更进一步
        super.init(suiteName: "ImageGalleryTestsFakeStub")!
    }

    // MARK: - UserSettings 用的 7 个 API override

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        if let value = value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
        // 不调 super — 跳过 cfprefsd
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return storage[defaultName]
    }

    override func string(forKey defaultName: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[defaultName] as? String
    }

    override func bool(forKey defaultName: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (storage[defaultName] as? Bool) ?? false
    }

    override func double(forKey defaultName: String) -> Double {
        lock.lock(); defer { lock.unlock() }
        return (storage[defaultName] as? Double) ?? 0
    }

    override func integer(forKey defaultName: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return (storage[defaultName] as? Int) ?? 0
    }

    override func removeObject(forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: defaultName)
    }

    // MARK: - V6.12.21: test-only cleanup, 比 removeObject(key) 多次快

    /// V6.12.21: 一次性清所有 key, 避免循环 removeObject 性能
    func clearAll() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll(keepingCapacity: true)
    }
}
