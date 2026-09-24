import CoreData
import Foundation

/// Accessors for attributes whose Swift type cannot be `@NSManaged` (`Decimal`, `Decimal?`, `Double?`).
extension NSManagedObject {
    func primitive<Value>(_ key: String) -> Value? {
        willAccessValue(forKey: key)
        defer { didAccessValue(forKey: key) }
        return primitiveValue(forKey: key) as? Value
    }

    func setPrimitive(_ value: Any?, for key: String) {
        willChangeValue(forKey: key)
        defer { didChangeValue(forKey: key) }
        setPrimitiveValue(value, forKey: key)
    }

    func decimal(_ key: String) -> Decimal? {
        let number: NSDecimalNumber? = primitive(key)
        return number?.decimalValue
    }

    func setDecimal(_ value: Decimal?, for key: String) {
        setPrimitive(value.map { NSDecimalNumber(decimal: $0) }, for: key)
    }
}
