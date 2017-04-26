// Extensions.swift
//


import Alamofire

extension Bool: JSONEncodable {
    func encodeToJSON() -> Any { return self as Any }
}

extension Float: JSONEncodable {
    func encodeToJSON() -> Any { return self as Any }
}

extension Int: JSONEncodable {
    func encodeToJSON() -> Any { return self as Any }
}

extension Int32: JSONEncodable {
    func encodeToJSON() -> Any { return NSNumber(value: self as Int32) }
}

extension Int64: JSONEncodable {
    func encodeToJSON() -> Any { return NSNumber(value: self as Int64) }
}

extension Double: JSONEncodable {
    func encodeToJSON() -> Any { return self as Any }
}

extension String: JSONEncodable {
    func encodeToJSON() -> Any { return self as Any }
}

private func encodeIfPossible<T>(_ object: T) -> Any {
    if let encodableObject = object as? JSONEncodable {
        return encodableObject.encodeToJSON()
    } else {
        return object as Any
    }
}

extension Array: JSONEncodable {
    func encodeToJSON() -> Any {
        return self.map(encodeIfPossible)
    }
}

extension Dictionary: JSONEncodable {
    func encodeToJSON() -> Any {
        var dictionary = [AnyHashable: Any]()
        for (key, value) in self {
            dictionary[key as! NSObject] = encodeIfPossible(value)
        }
        return dictionary as Any
    }
}

extension Data: JSONEncodable {
    func encodeToJSON() -> Any {
        return self.base64EncodedString(options: Data.Base64EncodingOptions())
    }
}

private let dateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    fmt.locale = Locale(identifier: "en_US_POSIX")
    return fmt
}()

extension Date: JSONEncodable {
    func encodeToJSON() -> Any {
        return dateFormatter.string(from: self) as Any
    }
}

extension UUID: JSONEncodable {
    func encodeToJSON() -> Any {
        return self.uuidString
    }
}


