// AlamofireImplementations.swift
//

import Alamofire

class AlamofireRequestBuilderFactory: RequestBuilderFactory {
    func getBuilder<T>() -> RequestBuilder<T>.Type {
        return AlamofireRequestBuilder<T>.self
    }
}

// Store manager to retain its reference
private var managerStore: [String: Alamofire.SessionManager] = [:]

open class AlamofireRequestBuilder<T>: RequestBuilder<T> {
    required public init(method: String, URLString: String, parameters: [String : Any]?, isBody: Bool, headers: [String : String] = [:]) {
        super.init(method: method, URLString: URLString, parameters: parameters, isBody: isBody, headers: headers)
    }

    /**
     May be overridden by a subclass if you want to control the session
     configuration.
     */
    open func createSessionManager() -> Alamofire.SessionManager {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = buildHeaders()
        return Alamofire.SessionManager(configuration: configuration)
    }

    /**
     May be overridden by a subclass if you want to control the Content-Type
     that is given to an uploaded form part.

     Return nil to use the default behavior (inferring the Content-Type from
     the file extension).  Return the desired Content-Type otherwise.
     */
    open func contentTypeForFormPart(fileURL: URL) -> String? {
        return nil
    }

    /**
     May be overridden by a subclass if you want to control the request
     configuration (e.g. to override the cache policy).
     */
    open func makeRequest(manager: SessionManager, method: HTTPMethod, encoding: ParameterEncoding) -> DataRequest {
        return manager.request(URLString, method: method, parameters: parameters, encoding: encoding)
    }

    override open func execute(_ completion: @escaping (_ response: Response<T>?, _ error: Error?) -> Void) {
        let managerId:String = UUID().uuidString
        // Create a new manager for each request to customize its request header
        let manager = createSessionManager()
        managerStore[managerId] = manager

        let encoding:ParameterEncoding = isBody ? JSONEncoding() : URLEncoding()

        let xMethod = Alamofire.HTTPMethod(rawValue: method)
        let fileKeys = parameters == nil ? [] : parameters!.filter { $1 is NSURL }
                                                           .map { $0.0 }

        if fileKeys.count > 0 {
            manager.upload(multipartFormData: { mpForm in
                for (k, v) in self.parameters! {
                    switch v {
                    case let fileURL as URL:
                        if let mimeType = self.contentTypeForFormPart(fileURL: fileURL) {
                            mpForm.append(fileURL, withName: k, fileName: fileURL.lastPathComponent, mimeType: mimeType)
                        }
                        else {
                            mpForm.append(fileURL, withName: k)
                        }
                        break
                    case let string as String:
                        mpForm.append(string.data(using: String.Encoding.utf8)!, withName: k)
                        break
                    case let number as NSNumber:
                        mpForm.append(number.stringValue.data(using: String.Encoding.utf8)!, withName: k)
                        break
                    default:
                        fatalError("Unprocessable value \(v) with key \(k)")
                        break
                    }
                }
                }, to: URLString, method: xMethod!, headers: nil, encodingCompletion: { encodingResult in
                switch encodingResult {
                case .success(let upload, _, _):
                    if let onProgressReady = self.onProgressReady {
                        onProgressReady(upload.progress)
                    }
                    self.processRequest(request: upload, managerId, completion)
                case .failure(let encodingError):
                    completion(nil, ErrorResponse.Error(415, nil, encodingError))
                }
            })
        } else {
            let request = makeRequest(manager: manager, method: xMethod!, encoding: encoding)
            if let onProgressReady = self.onProgressReady {
                onProgressReady(request.progress)
            }
            processRequest(request: request, managerId, completion)
        }

    }

    private func processRequest(request: DataRequest, _ managerId: String, _ completion: @escaping (_ response: Response<T>?, _ error: Error?) -> Void) {
        
        let cleanupRequest = {
            _ = managerStore.removeValue(forKey: managerId)
        }

        let validatedRequest = request.validate()

        switch T.self {
        case is String.Type:
            validatedRequest.responseString(completionHandler: { (stringResponse) in
                cleanupRequest()

                if stringResponse.result.isFailure {
                    completion(
                        nil,
                        ErrorResponse.Error(stringResponse.response?.statusCode ?? 500, stringResponse.data, stringResponse.result.error as Error!)
                    )
                    return
                }

                completion(
                    Response(
                        response: stringResponse.response!,
                        body: ((stringResponse.result.value ?? "") as! T)
                    ),
                    nil
                )
            })
        case is Void.Type:
            validatedRequest.responseData(completionHandler: { (voidResponse) in
                cleanupRequest()

                if voidResponse.result.isFailure {
                    completion(
                        nil,
                        ErrorResponse.Error(voidResponse.response?.statusCode ?? 500, voidResponse.data, voidResponse.result.error!)
                    )
                    return
                }

                completion(
                    Response(
                        response: voidResponse.response!,
                        body: nil),
                    nil
                )
            })
        case is Data.Type:
            validatedRequest.responseData(completionHandler: { (dataResponse) in
                cleanupRequest()

                if (dataResponse.result.isFailure) {
                    completion(
                        nil,
                        ErrorResponse.Error(dataResponse.response?.statusCode ?? 500, dataResponse.data, dataResponse.result.error!)
                    )
                    return
                }

                completion(
                    Response(
                        response: dataResponse.response!,
                        body: (dataResponse.data as! T)
                    ),
                    nil
                )
            })
        default:
            validatedRequest.responseJSON(options: .allowFragments) { response in
                cleanupRequest()

                if response.result.isFailure {
                    
                    if response.response?.statusCode == 400 {
                        
                        
                        do {
                            let json = try JSONSerialization.jsonObject(with: response.data!, options: .allowFragments)
                            
                            let body = Decoders.decode(clazz: ModelError.self, source: json as AnyObject)
                            
                            completion(nil, ErrorResponse.Error(response.response?.statusCode ?? 500, response.data, body))
                            
                            return
                        } catch {}
                        
                    }
                    
                    completion(nil, ErrorResponse.Error(response.response?.statusCode ?? 500, response.data, response.result.error!))
                    
                    return
                }

                // handle HTTP 204 No Content
                // NSNull would crash decoders
                if response.response?.statusCode == 204 && response.result.value is NSNull{
                    completion(nil, nil)
                    return;
                }

                if () is T {
                    completion(Response(response: response.response!, body: (() as! T)), nil)
                    return
                }
                if let json: Any = response.result.value {
                    let body = Decoders.decode(clazz: T.self, source: json as AnyObject)
                    completion(Response(response: response.response!, body: body), nil)
                    return
                } else if "" is T {
                    // swagger-parser currently doesn't support void, which will be fixed in future swagger-parser release
                    // https://github.com/swagger-api/swagger-parser/pull/34
                    completion(Response(response: response.response!, body: ("" as! T)), nil)
                    return
                }

                completion(nil, ErrorResponse.Error(500, nil, NSError(domain: "localhost", code: 500, userInfo: ["reason": "unreacheable code"])))
            }
        }
    }

    private func buildHeaders() -> [String: String] {
        var httpHeaders = SessionManager.defaultHTTPHeaders
        for (key, value) in self.headers {
            httpHeaders[key] = value
        }
        return httpHeaders
    }
}
