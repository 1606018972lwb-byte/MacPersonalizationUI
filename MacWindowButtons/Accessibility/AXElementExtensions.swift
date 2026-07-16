import ApplicationServices

extension AXUIElement {
    /// 读取一个 Accessibility 属性，并保留错误日志用于兼容性排查。
    func copyAttribute(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard error == .success else {
            if error != .attributeUnsupported && error != .noValue {
                NSLog("[MacWindowButtons] 读取 AX 属性 %@ 失败：%d", attribute, error.rawValue)
            }
            return nil
        }
        return value
    }

    /// 读取字符串属性。
    func stringAttribute(_ attribute: String) -> String? {
        copyAttribute(attribute) as? String
    }

    /// 读取布尔属性。
    func boolAttribute(_ attribute: String) -> Bool? {
        guard let number = copyAttribute(attribute) as? NSNumber else {
            return nil
        }
        return number.boolValue
    }

    /// 读取 CGPoint 类型的 AXValue。
    func pointAttribute(_ attribute: String) -> CGPoint? {
        guard let value = copyAttribute(attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        // Core Foundation 不提供可选转换；前面的 CFTypeID 校验保证该转换安全。
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    /// 读取 CGSize 类型的 AXValue。
    func sizeAttribute(_ attribute: String) -> CGSize? {
        guard let value = copyAttribute(attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        // Core Foundation 不提供可选转换；前面的 CFTypeID 校验保证该转换安全。
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    /// 判断属性是否允许写入；不支持的属性会返回 false，而不是中断应用。
    func isAttributeSettable(_ attribute: String) -> Bool {
        var isSettable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(self, attribute as CFString, &isSettable)
        return error == .success && isSettable.boolValue
    }

    /// 写入布尔属性并返回操作结果。
    @discardableResult
    func setBooleanAttribute(_ attribute: String, value: Bool) -> Bool {
        let error = AXUIElementSetAttributeValue(
            self,
            attribute as CFString,
            value ? kCFBooleanTrue : kCFBooleanFalse
        )
        if error != .success {
            NSLog("[MacWindowButtons] 写入 AX 布尔属性 %@ 失败：%d", attribute, error.rawValue)
        }
        return error == .success
    }

    /// 写入窗口坐标。
    @discardableResult
    func setPointAttribute(_ attribute: String, value: CGPoint) -> Bool {
        var mutableValue = value
        guard let axValue = AXValueCreate(.cgPoint, &mutableValue) else {
            NSLog("[MacWindowButtons] 无法创建 CGPoint AXValue")
            return false
        }
        return setAttribute(attribute, value: axValue)
    }

    /// 写入窗口尺寸。
    @discardableResult
    func setSizeAttribute(_ attribute: String, value: CGSize) -> Bool {
        var mutableValue = value
        guard let axValue = AXValueCreate(.cgSize, &mutableValue) else {
            NSLog("[MacWindowButtons] 无法创建 CGSize AXValue")
            return false
        }
        return setAttribute(attribute, value: axValue)
    }

    private func setAttribute(_ attribute: String, value: CFTypeRef) -> Bool {
        let error = AXUIElementSetAttributeValue(self, attribute as CFString, value)
        if error != .success {
            NSLog("[MacWindowButtons] 写入 AX 属性 %@ 失败：%d", attribute, error.rawValue)
        }
        return error == .success
    }
}
