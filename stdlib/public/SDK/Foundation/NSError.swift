//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CoreFoundation
import Darwin

/// Describes an error that provides localized messages describing why
/// an error occurred and provides more information about the error.
public protocol LocalizedError : Error {
  /// A localized message describing what error occurred.
  var errorDescription: String? { get }

  /// A localized message describing the reason for the failure.
  var failureReason: String? { get }

  /// A localized message describing how one might recover from the failure.
  var recoverySuggestion: String? { get }

  /// A localized message providing "help" text if the user requests help.
  var helpAnchor: String? { get }
}

public extension LocalizedError {
  var errorDescription: String? { return nil }
  var failureReason: String? { return nil }
  var recoverySuggestion: String? { return nil }
  var helpAnchor: String? { return nil }
}

@_silgen_name("NS_Swift_performErrorRecoverySelector")
internal func NS_Swift_performErrorRecoverySelector(
  delegate: AnyObject?,
  selector: Selector,
  success: ObjCBool,
  contextInfo: UnsafeMutablePointer<Void>?)

/// Class that implements the informal protocol
/// NSErrorRecoveryAttempting, which is used by NSError when it
/// attempts recovery from an error.
class _NSErrorRecoveryAttempter {
  @objc(attemptRecoveryFromError:optionIndex:delegate:didRecoverSelector:contextInfo:)
  func attemptRecovery(fromError nsError: NSError,
                       optionIndex recoveryOptionIndex: Int,
                       delegate: AnyObject?,
                       didRecoverSelector: Selector,
                       contextInfo: UnsafeMutablePointer<Void>?) {
    let error = nsError as Error as! RecoverableError
    error.attemptRecovery(optionIndex: recoveryOptionIndex) { success in
      NS_Swift_performErrorRecoverySelector(
        delegate: delegate,
        selector: didRecoverSelector,
        success: ObjCBool(success),
        contextInfo: contextInfo)
    }
  }

  @objc(attemptRecoveryFromError:optionIndex:)
  func attemptRecovery(fromError nsError: NSError,
                       optionIndex recoveryOptionIndex: Int) -> Bool {
    let error = nsError as Error as! RecoverableError
    return error.attemptRecovery(optionIndex: recoveryOptionIndex)
  }
}

/// Describes an error that may be recoverably by presenting several
/// potential recovery options to the user.
public protocol RecoverableError : Error {
  /// Provides a set of possible recovery options to present to the user.
  var recoveryOptions: [String] { get }

  /// Attempt to recover from this error when the user selected the
  /// option at the given index. This routine must call handler and
  /// indicate whether recovery was successful (or not).
  ///
  /// This entry point is used for recovery of errors handled at a
  /// "document" granularity, that do not affect the entire
  /// application.
  func attemptRecovery(optionIndex recoveryOptionIndex: Int,
                       resultHandler handler: (recovered: Bool) -> Void)

  /// Attempt to recover from this error when the user selected the
  /// option at the given index. Returns true to indicate
  /// successful recovery, and false otherwise.
  ///
  /// This entry point is used for recovery of errors handled at
  /// the "application" granularity, where nothing else in the
  /// application can proceed until the attmpted error recovery
  /// completes.
  func attemptRecovery(optionIndex recoveryOptionIndex: Int) -> Bool
}

public extension RecoverableError {
  /// Default implementation that uses the application-model recovery
  /// mechanism (``attemptRecovery(optionIndex:)``) to implement
  /// document-modal recovery.
  func attemptRecovery(optionIndex recoveryOptionIndex: Int,
                       resultHandler handler: (recovered: Bool) -> Void) {
    handler(recovered: attemptRecovery(optionIndex: recoveryOptionIndex))
  }
}

/// Describes an error type that specifically provides a domain, code,
/// and user-info dictionary.
public protocol CustomNSError : Error {
  /// The domain of the error.
  static var errorDomain: String { get }

  /// The error code within the given domain.
  var errorCode: Int { get }

  /// The user-info dictionary.
  var errorUserInfo: [String : AnyObject] { get }
}

public extension Error where Self : CustomNSError {
  /// Default implementation for customized NSErrors.
  var _domain: String { return Self.errorDomain }

  /// Default implementation for customized NSErrors.
  var _code: Int { return self.errorCode }
}

public extension Error {
  /// Retrieve the localized description for this error.
  var localizedDescription: String {
    return (self as NSError).localizedDescription
  }
}

/// Retrieve the default userInfo dictionary for a given error.
@_silgen_name("swift_Foundation_getErrorDefaultUserInfo")
public func _swift_Foundation_getErrorDefaultUserInfo(_ error: Error)
  -> AnyObject? {
  let hasUserInfoValueProvider: Bool

  // If the OS supports user info value providers, use those
  // to lazily populate the user-info dictionary for this domain.
  if #available(OSX 10.11, iOS 9.0, tvOS 9.0, watchOS 2.0, *) {
    // Note: the Cocoa error domain specifically excluded from
    // user-info value providers.
    let domain = error._domain
    if domain != NSCocoaErrorDomain {
      if NSError.userInfoValueProvider(forDomain: domain) == nil {
        NSError.setUserInfoValueProvider(forDomain: domain) { (nsError, key) in
          let error = nsError as Error

          switch key {
          case NSLocalizedDescriptionKey:
            return (error as? LocalizedError)?.errorDescription

          case NSLocalizedFailureReasonErrorKey:
            return (error as? LocalizedError)?.failureReason

          case NSLocalizedRecoverySuggestionErrorKey:
            return (error as? LocalizedError)?.recoverySuggestion

          case NSHelpAnchorErrorKey:
            return (error as? LocalizedError)?.helpAnchor

          case NSLocalizedRecoveryOptionsErrorKey:
            return (error as? RecoverableError)?.recoveryOptions

          case NSRecoveryAttempterErrorKey:
            if error is RecoverableError {
              return _NSErrorRecoveryAttempter()
            }
            return nil

          default:
            return nil
          }
        }
      }
      assert(NSError.userInfoValueProvider(forDomain: domain) != nil)

      hasUserInfoValueProvider = true
    } else {
      hasUserInfoValueProvider = false
    }
  } else {
    hasUserInfoValueProvider = false
  }

  // Populate the user-info dictionary 
  var result: [String : AnyObject]

  // Initialize with custom user-info.
  if let customNSError = error as? CustomNSError {
    result = customNSError.errorUserInfo
  } else {
    result = [:]
  }

  // Handle localized errors. If we registered a user-info value
  // provider, these will computed lazily.
  if !hasUserInfoValueProvider,
     let localizedError = error as? LocalizedError {
    if let description = localizedError.errorDescription {
      result[NSLocalizedDescriptionKey] = description as AnyObject
    }
    
    if let reason = localizedError.failureReason {
      result[NSLocalizedFailureReasonErrorKey] = reason as AnyObject
    }
    
    if let suggestion = localizedError.recoverySuggestion {   
      result[NSLocalizedRecoverySuggestionErrorKey] = suggestion as AnyObject
    }
    
    if let helpAnchor = localizedError.helpAnchor {   
      result[NSHelpAnchorErrorKey] = helpAnchor as AnyObject
    }
  }

  // Handle recoverable errors. If we registered a user-info value
  // provider, these will computed lazily.
  if !hasUserInfoValueProvider,
     let recoverableError = error as? RecoverableError {
    result[NSLocalizedRecoveryOptionsErrorKey] =
      recoverableError.recoveryOptions as AnyObject
    result[NSRecoveryAttempterErrorKey] = _NSErrorRecoveryAttempter()
  }

  return result as AnyObject
}

// NSError and CFError conform to the standard Error protocol. Compiler
// magic allows this to be done as a "toll-free" conversion when an NSError
// or CFError is used as an Error existential.

extension NSError : Error {
  public var _domain: String { return domain }
  public var _code: Int { return code }
  public var _userInfo: AnyObject? { return userInfo as AnyObject }
}

extension CFError : Error {
  public var _domain: String {
    return CFErrorGetDomain(self) as String
  }

  public var _code: Int {
    return CFErrorGetCode(self)
  }

  public var _userInfo: AnyObject? {
    return CFErrorCopyUserInfo(self) as AnyObject?
  }
}

// An error value to use when an Objective-C API indicates error
// but produces a nil error object.
public enum _GenericObjCError : Error {
  case nilError
}

/// An internal protocol to represent Swift error enums that map to standard
/// Cocoa NSError domains.
public protocol _ObjectiveCBridgeableError : Error {
  /// Produce a value of the error type corresponding to the given NSError,
  /// or return nil if it cannot be bridged.
  init?(_bridgedNSError: NSError)
}

/// A hook for the runtime to use _ObjectiveCBridgeableError in order to
/// attempt an "errorTypeValue as? SomeError" cast.
///
/// If the bridge succeeds, the bridged value is written to the uninitialized
/// memory pointed to by 'out', and true is returned. Otherwise, 'out' is
/// left uninitialized, and false is returned.
@_silgen_name("swift_stdlib_bridgeNSErrorToError")
public func _stdlib_bridgeNSErrorToError<
  T : _ObjectiveCBridgeableError
>(_ error: NSError, out: UnsafeMutablePointer<T>) -> Bool {
  if let bridged = T(_bridgedNSError: error) {
    out.initialize(with: bridged)
    return true
  } else {
    return false
  }
}

/// Helper protocol for _BridgedNSError, which used to provide
/// default implementations.
public protocol __BridgedNSError : Error {
  static var _nsErrorDomain: String { get }
}

// Allow two bridged NSError types to be compared.
public func ==<T: __BridgedNSError>(lhs: T, rhs: T) -> Bool
  where T: RawRepresentable, T.RawValue: SignedInteger {
  return lhs.rawValue.toIntMax() == rhs.rawValue.toIntMax()
}

public extension __BridgedNSError 
    where Self: RawRepresentable, Self.RawValue: SignedInteger {
  public final var _domain: String { return Self._nsErrorDomain }
  public final var _code: Int { return Int(rawValue.toIntMax()) }

  public init?(rawValue: RawValue) {
    self = unsafeBitCast(rawValue, to: Self.self)
  }

  public init?(_bridgedNSError: NSError) {
    if _bridgedNSError.domain != Self._nsErrorDomain {
      return nil
    }

    self.init(rawValue: RawValue(IntMax(_bridgedNSError.code)))
  }

  public final var hashValue: Int { return _code }
}

// Allow two bridged NSError types to be compared.
public func ==<T: __BridgedNSError>(lhs: T, rhs: T) -> Bool
  where T: RawRepresentable, T.RawValue: UnsignedInteger {
  return lhs.rawValue.toUIntMax() == rhs.rawValue.toUIntMax()
}


public extension __BridgedNSError
    where Self: RawRepresentable, Self.RawValue: UnsignedInteger {
  public final var _domain: String { return Self._nsErrorDomain }
  public final var _code: Int {
    return Int(bitPattern: UInt(rawValue.toUIntMax()))
  }

  public init?(rawValue: RawValue) {
    self = unsafeBitCast(rawValue, to: Self.self)
  }

  public init?(_bridgedNSError: NSError) {
    if _bridgedNSError.domain != Self._nsErrorDomain {
      return nil
    }

    self.init(rawValue: RawValue(UIntMax(UInt(_bridgedNSError.code))))
  }

  public final var hashValue: Int { return _code }
}

/// Describes a raw representable type that is bridged to a particular
/// NSError domain.
///
/// This protocol is used primarily to generate the conformance to
/// _ObjectiveCBridgeableError for such an enum.
public protocol _BridgedNSError : __BridgedNSError,
                                  RawRepresentable,
                                  _ObjectiveCBridgeableError,
                                  Hashable {
  /// The NSError domain to which this type is bridged.
  static var _nsErrorDomain: String { get }
}

/// Describes a bridged error that stores the underlying NSError, so
/// it can be queried.
public protocol _BridgedStoredNSError :
     __BridgedNSError, _ObjectiveCBridgeableError, CustomNSError,
     Hashable {
  /// The type of an error code.
  associatedtype Code: _ErrorCodeProtocol

  /// The error code for the given error.
  var code: Code { get }

  //// Retrieves the embedded NSError.
  var _nsError: NSError { get }

  /// Create a new instance of the error type with the given embedded
  /// NSError.
  ///
  /// The \c error must have the appropriate domain for this error
  /// type.
  init(_nsError error: NSError)
}

/// Various helper implementations for _BridgedStoredNSError
public extension _BridgedStoredNSError
    where Code: RawRepresentable, Code.RawValue: SignedInteger {
  // FIXME: Generalize to Integer.
  public var code: Code {
    return Code(rawValue: numericCast(_nsError.code))!
  }

  /// Initialize an error within this domain with the given ``code``
  /// and ``userInfo``.
  public init(_ code: Code, userInfo: [String : AnyObject] = [:]) {
    self.init(_nsError: NSError(domain: Self._nsErrorDomain,
                                code: numericCast(code.rawValue),
                                userInfo: userInfo))
  }

  /// The user-info dictionary for an error that was bridged from
  /// NSError.
  var userInfo: [String : AnyObject] { return errorUserInfo }
}

/// Various helper implementations for _BridgedStoredNSError
public extension _BridgedStoredNSError
    where Code: RawRepresentable, Code.RawValue: UnsignedInteger {
  // FIXME: Generalize to Integer.
  public var code: Code {
    return Code(rawValue: numericCast(_nsError.code))!
  }

  /// Initialize an error within this domain with the given ``code``
  /// and ``userInfo``.
  public init(_ code: Code, userInfo: [String : AnyObject] = [:]) {
    self.init(_nsError: NSError(domain: Self._nsErrorDomain,
                                code: numericCast(code.rawValue),
                                userInfo: userInfo))
  }
}

/// Implementation of __BridgedNSError for all _BridgedStoredNSErrors.
public extension _BridgedStoredNSError {
  /// Default implementation of ``init(_bridgedNSError)`` to provide
  /// bridging from NSError.
  public init?(_bridgedNSError error: NSError) {
    if error.domain != Self._nsErrorDomain {
      return nil
    }

    self.init(_nsError: error)
  }
}

/// Implementation of CustomNSError for all _BridgedStoredNSErrors.
public extension _BridgedStoredNSError {
  // FIXME: Would prefer to have a clear "extract an NSError
  // directly" operation.

  static var errorDomain: String { return _nsErrorDomain }

  var errorCode: Int { return _nsError.code }

  var errorUserInfo: [String : AnyObject] {
    var result: [String : AnyObject] = [:]
    for (key, value) in _nsError.userInfo {
      guard let stringKey = key as? String else { continue }
      result[stringKey] = value
    }
    return result;
  }
}

/// Implementation of Hashable for all _BridgedStoredNSErrors.
public extension _BridgedStoredNSError {
  var hashValue: Int {
    return _nsError.hashValue
  }
}

/// Describes the code of an error.
public protocol _ErrorCodeProtocol : Equatable {
  /// The corresponding error code.
  associatedtype _ErrorType

  // FIXME: We want _ErrorType to be _BridgedStoredNSError and have its
  // Code match Self, but we cannot express those requirements yet.
}

/// Allow one to match an error code against an arbitrary error.
public func ~= <Code: _ErrorCodeProtocol>(match: Code, error: Error)
    -> Bool
    where Code._ErrorType: _BridgedStoredNSError {
  guard let specificError = error as? Code._ErrorType else { return false }

  // FIXME: Work around IRGen crash when we set Code == Code._ErrorType.Code.
  let specificCode = specificError.code as! Code
  return match == specificCode
}

public func == <T: _BridgedStoredNSError>(lhs: T, rhs: T) -> Bool {
  return lhs._nsError.isEqual(rhs._nsError)
}

@available(*, unavailable, renamed: "CocoaError")
public typealias NSCocoaError = CocoaError

/// Describes errors within the Cocoa error domain.
public struct CocoaError : _BridgedStoredNSError {
  public let _nsError: NSError

  public init(_nsError error: NSError) {
    precondition(error.domain == NSCocoaErrorDomain)
    self._nsError = error
  }

  public static var _nsErrorDomain: String { return NSCocoaErrorDomain }

  /// The error code itself.
  public struct Code : RawRepresentable, _ErrorCodeProtocol {
    public typealias _ErrorType = CocoaError

    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }
  }
}

public extension CocoaError {
  private var _userInfo: [NSObject : AnyObject] {
    return (self as NSError).userInfo
  }

  /// The file path associated with the error, if any.
  var filePath: String? {
    return _userInfo[NSFilePathErrorKey] as? String
  }

  /// The string encoding associated with this error, if any.
  var stringEncoding: String.Encoding? {
    return (_userInfo[NSStringEncodingErrorKey] as? NSNumber)
             .map { String.Encoding(rawValue: $0.uintValue) }
  }

  /// The underlying error behind this error, if any.
  var underlying: Error? {
    return _userInfo[NSUnderlyingErrorKey] as? Error
  }

  /// The URL associated with this error, if any.
  var url: URL? {
    return _userInfo[NSURLErrorKey] as? URL
  }
}

extension CocoaError.Code {
  public static var fileNoSuchFileError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4)
  }
  public static var fileLockingError: CocoaError.Code {
    return CocoaError.Code(rawValue: 255)
  }
  public static var fileReadUnknownError: CocoaError.Code {
    return CocoaError.Code(rawValue: 256)
  }
  public static var fileReadNoPermissionError: CocoaError.Code {
    return CocoaError.Code(rawValue: 257)
  }
  public static var fileReadInvalidFileNameError: CocoaError.Code {
    return CocoaError.Code(rawValue: 258)
  }
  public static var fileReadCorruptFileError: CocoaError.Code {
    return CocoaError.Code(rawValue: 259)
  }
  public static var fileReadNoSuchFileError: CocoaError.Code {
    return CocoaError.Code(rawValue: 260)
  }
  public static var fileReadInapplicableStringEncodingError: CocoaError.Code {
    return CocoaError.Code(rawValue: 261)
  }
  public static var fileReadUnsupportedSchemeError: CocoaError.Code {
    return CocoaError.Code(rawValue: 262)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var fileReadTooLargeError: CocoaError.Code {
    return CocoaError.Code(rawValue: 263)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var fileReadUnknownStringEncodingError: CocoaError.Code {
    return CocoaError.Code(rawValue: 264)
  }

  public static var fileWriteUnknownError: CocoaError.Code {
    return CocoaError.Code(rawValue: 512)
  }
  public static var fileWriteNoPermissionError: CocoaError.Code {
    return CocoaError.Code(rawValue: 513)
  }
  public static var fileWriteInvalidFileNameError: CocoaError.Code {
    return CocoaError.Code(rawValue: 514)
  }

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 5.0)
  public static var fileWriteFileExistsError: CocoaError.Code {
    return CocoaError.Code(rawValue: 516)
  }

  public static var fileWriteInapplicableStringEncodingError: CocoaError.Code {
    return CocoaError.Code(rawValue: 517)
  }
  public static var fileWriteUnsupportedSchemeError: CocoaError.Code {
    return CocoaError.Code(rawValue: 518)
  }
  public static var fileWriteOutOfSpaceError: CocoaError.Code {
    return CocoaError.Code(rawValue: 640)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var fileWriteVolumeReadOnlyError: CocoaError.Code {
    return CocoaError.Code(rawValue: 642)
  }

  @available(OSX, introduced: 10.11) @available(iOS, unavailable)
  public static var fileManagerUnmountUnknownError: CocoaError.Code {
    return CocoaError.Code(rawValue: 768)
  }

  @available(OSX, introduced: 10.11) @available(iOS, unavailable)
  public static var fileManagerUnmountBusyError: CocoaError.Code {
    return CocoaError.Code(rawValue: 769)
  }

  public static var keyValueValidationError: CocoaError.Code {
    return CocoaError.Code(rawValue: 1024)
  }
  public static var formattingError: CocoaError.Code {
    return CocoaError.Code(rawValue: 2048)
  }
  public static var userCancelledError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3072)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var featureUnsupportedError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3328)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableNotLoadableError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3584)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableArchitectureMismatchError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3585)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableRuntimeMismatchError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3586)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableLoadError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3587)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableLinkError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3588)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListReadCorruptError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3840)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListReadUnknownVersionError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3841)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListReadStreamError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3842)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListWriteStreamError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3851)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var propertyListWriteInvalidError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3852)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var xpcConnectionInterrupted: CocoaError.Code {
    return CocoaError.Code(rawValue: 4097)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var xpcConnectionInvalid: CocoaError.Code {
    return CocoaError.Code(rawValue: 4099)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var xpcConnectionReplyInvalid: CocoaError.Code {
    return CocoaError.Code(rawValue: 4101)
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public static var ubiquitousFileUnavailableError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4353)
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public static var ubiquitousFileNotUploadedDueToQuotaError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4354)
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public static var ubiquitousFileUbiquityServerNotAvailable: CocoaError.Code {
    return CocoaError.Code(rawValue: 4355)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityHandoffFailedError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4608)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityConnectionUnavailableError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4609)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityRemoteApplicationTimedOutError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4610)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityHandoffUserInfoTooLargeError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4611)
  }

  @available(OSX, introduced: 10.11) @available(iOS, introduced: 9.0)
  public static var coderReadCorruptError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4864)
  }

  @available(OSX, introduced: 10.11) @available(iOS, introduced: 9.0)
  public static var coderValueNotFoundError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4865)
  }
}

extension CocoaError {
  public static var fileNoSuchFileError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4)
  }
  public static var fileLockingError: CocoaError.Code {
    return CocoaError.Code(rawValue: 255)
  }
  public static var fileReadUnknownError: CocoaError.Code {
    return CocoaError.Code(rawValue: 256)
  }
  public static var fileReadNoPermissionError: CocoaError.Code {
    return CocoaError.Code(rawValue: 257)
  }
  public static var fileReadInvalidFileNameError: CocoaError.Code {
    return CocoaError.Code(rawValue: 258)
  }
  public static var fileReadCorruptFileError: CocoaError.Code {
    return CocoaError.Code(rawValue: 259)
  }
  public static var fileReadNoSuchFileError: CocoaError.Code {
    return CocoaError.Code(rawValue: 260)
  }
  public static var fileReadInapplicableStringEncodingError: CocoaError.Code {
    return CocoaError.Code(rawValue: 261)
  }
  public static var fileReadUnsupportedSchemeError: CocoaError.Code {
    return CocoaError.Code(rawValue: 262)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var fileReadTooLargeError: CocoaError.Code {
    return CocoaError.Code(rawValue: 263)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var fileReadUnknownStringEncodingError: CocoaError.Code {
    return CocoaError.Code(rawValue: 264)
  }

  public static var fileWriteUnknownError: CocoaError.Code {
    return CocoaError.Code(rawValue: 512)
  }
  public static var fileWriteNoPermissionError: CocoaError.Code {
    return CocoaError.Code(rawValue: 513)
  }
  public static var fileWriteInvalidFileNameError: CocoaError.Code {
    return CocoaError.Code(rawValue: 514)
  }

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 5.0)
  public static var fileWriteFileExistsError: CocoaError.Code {
    return CocoaError.Code(rawValue: 516)
  }

  public static var fileWriteInapplicableStringEncodingError: CocoaError.Code {
    return CocoaError.Code(rawValue: 517)
  }
  public static var fileWriteUnsupportedSchemeError: CocoaError.Code {
    return CocoaError.Code(rawValue: 518)
  }
  public static var fileWriteOutOfSpaceError: CocoaError.Code {
    return CocoaError.Code(rawValue: 640)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var fileWriteVolumeReadOnlyError: CocoaError.Code {
    return CocoaError.Code(rawValue: 642)
  }

  @available(OSX, introduced: 10.11) @available(iOS, unavailable)
  public static var fileManagerUnmountUnknownError: CocoaError.Code {
    return CocoaError.Code(rawValue: 768)
  }

  @available(OSX, introduced: 10.11) @available(iOS, unavailable)
  public static var fileManagerUnmountBusyError: CocoaError.Code {
    return CocoaError.Code(rawValue: 769)
  }

  public static var keyValueValidationError: CocoaError.Code {
    return CocoaError.Code(rawValue: 1024)
  }
  public static var formattingError: CocoaError.Code {
    return CocoaError.Code(rawValue: 2048)
  }
  public static var userCancelledError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3072)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var featureUnsupportedError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3328)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableNotLoadableError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3584)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableArchitectureMismatchError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3585)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableRuntimeMismatchError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3586)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableLoadError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3587)
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableLinkError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3588)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListReadCorruptError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3840)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListReadUnknownVersionError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3841)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListReadStreamError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3842)
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public static var propertyListWriteStreamError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3851)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var propertyListWriteInvalidError: CocoaError.Code {
    return CocoaError.Code(rawValue: 3852)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var xpcConnectionInterrupted: CocoaError.Code {
    return CocoaError.Code(rawValue: 4097)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var xpcConnectionInvalid: CocoaError.Code {
    return CocoaError.Code(rawValue: 4099)
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public static var xpcConnectionReplyInvalid: CocoaError.Code {
    return CocoaError.Code(rawValue: 4101)
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public static var ubiquitousFileUnavailableError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4353)
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public static var ubiquitousFileNotUploadedDueToQuotaError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4354)
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public static var ubiquitousFileUbiquityServerNotAvailable: CocoaError.Code {
    return CocoaError.Code(rawValue: 4355)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityHandoffFailedError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4608)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityConnectionUnavailableError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4609)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityRemoteApplicationTimedOutError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4610)
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var userActivityHandoffUserInfoTooLargeError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4611)
  }

  @available(OSX, introduced: 10.11) @available(iOS, introduced: 9.0)
  public static var coderReadCorruptError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4864)
  }

  @available(OSX, introduced: 10.11) @available(iOS, introduced: 9.0)
  public static var coderValueNotFoundError: CocoaError.Code {
    return CocoaError.Code(rawValue: 4865)
  }
}

extension CocoaError {
  @available(OSX, introduced: 10.11) @available(iOS, introduced: 9.0)
  public var isCoderError: Bool {
    return code.rawValue >= 4864 && code.rawValue <= 4991
  }

  @available(OSX, introduced: 10.5) @available(iOS, introduced: 2.0)
  public var isExecutableError: Bool {
    return code.rawValue >= 3584 && code.rawValue <= 3839
  }

  public var isFileError: Bool {
    return code.rawValue >= 0 && code.rawValue <= 1023
  }

  public var isFormattingError: Bool {
    return code.rawValue >= 2048 && code.rawValue <= 2559
  }

  @available(OSX, introduced: 10.6) @available(iOS, introduced: 4.0)
  public var isPropertyListError: Bool {
    return code.rawValue >= 3840 && code.rawValue <= 4095
  }

  @available(OSX, introduced: 10.9) @available(iOS, introduced: 7.0)
  public var isUbiquitousFileError: Bool {
    return code.rawValue >= 4352 && code.rawValue <= 4607
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public var isUserActivityError: Bool {
    return code.rawValue >= 4608 && code.rawValue <= 4863
  }

  public var isValidationError: Bool {
    return code.rawValue >= 1024 && code.rawValue <= 2047
  }

  @available(OSX, introduced: 10.8) @available(iOS, introduced: 6.0)
  public var isXPCConnectionError: Bool {
    return code.rawValue >= 4096 && code.rawValue <= 4224
  }
}

extension CocoaError.Code {
  @available(*, unavailable, renamed: "fileNoSuchFileError")
  public static var FileNoSuchFileError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileLockingError")
  public static var FileLockingError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadUnknownError")
  public static var FileReadUnknownError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadNoPermissionError")
  public static var FileReadNoPermissionError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadInvalidFileNameError")
  public static var FileReadInvalidFileNameError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadCorruptFileError")
  public static var FileReadCorruptFileError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadNoSuchFileError")
  public static var FileReadNoSuchFileError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadInapplicableStringEncodingError")
  public static var FileReadInapplicableStringEncodingError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadUnsupportedSchemeError")
  public static var FileReadUnsupportedSchemeError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadTooLargeError")
  public static var FileReadTooLargeError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileReadUnknownStringEncodingError")
  public static var FileReadUnknownStringEncodingError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteUnknownError")
  public static var FileWriteUnknownError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteNoPermissionError")
  public static var FileWriteNoPermissionError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteInvalidFileNameError")
  public static var FileWriteInvalidFileNameError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteFileExistsError")
  public static var FileWriteFileExistsError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteInapplicableStringEncodingError")
  public static var FileWriteInapplicableStringEncodingError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteUnsupportedSchemeError")
  public static var FileWriteUnsupportedSchemeError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteOutOfSpaceError")
  public static var FileWriteOutOfSpaceError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileWriteVolumeReadOnlyError")
  public static var FileWriteVolumeReadOnlyError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileManagerUnmountUnknownError")
  public static var FileManagerUnmountUnknownError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileManagerUnmountBusyError")
  public static var FileManagerUnmountBusyError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "keyValueValidationError")
  public static var KeyValueValidationError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "formattingError")
  public static var FormattingError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userCancelledError")
  public static var UserCancelledError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "featureUnsupportedError")
  public static var FeatureUnsupportedError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "executableNotLoadableError")
  public static var ExecutableNotLoadableError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "executableArchitectureMismatchError")
  public static var ExecutableArchitectureMismatchError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "executableRuntimeMismatchError")
  public static var ExecutableRuntimeMismatchError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "executableLoadError")
  public static var ExecutableLoadError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "executableLinkError")
  public static var ExecutableLinkError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "propertyListReadCorruptError")
  public static var PropertyListReadCorruptError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "propertyListReadUnknownVersionError")
  public static var PropertyListReadUnknownVersionError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "propertyListReadStreamError")
  public static var PropertyListReadStreamError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "propertyListWriteStreamError")
  public static var PropertyListWriteStreamError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "propertyListWriteInvalidError")
  public static var PropertyListWriteInvalidError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "xpcConnectionInterrupted")
  public static var XPCConnectionInterrupted: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "xpcConnectionInvalid")
  public static var XPCConnectionInvalid: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "xpcConnectionReplyInvalid")
  public static var XPCConnectionReplyInvalid: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "ubiquitousFileUnavailableError")
  public static var UbiquitousFileUnavailableError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "ubiquitousFileNotUploadedDueToQuotaError")
  public static var UbiquitousFileNotUploadedDueToQuotaError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "ubiquitousFileUbiquityServerNotAvailable")
  public static var UbiquitousFileUbiquityServerNotAvailable: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userActivityHandoffFailedError")
  public static var UserActivityHandoffFailedError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userActivityConnectionUnavailableError")
  public static var UserActivityConnectionUnavailableError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userActivityRemoteApplicationTimedOutError")
  public static var UserActivityRemoteApplicationTimedOutError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userActivityHandoffUserInfoTooLargeError")
  public static var UserActivityHandoffUserInfoTooLargeError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "coderReadCorruptError")
  public static var CoderReadCorruptError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "coderValueNotFoundError")
  public static var CoderValueNotFoundError: CocoaError.Code {
    fatalError("unavailable accessor can't be called")
  }
}

/// Describes errors in the URL error domain.
public struct URLError : _BridgedStoredNSError {
  public let _nsError: NSError

  public init(_nsError error: NSError) {
    precondition(error.domain == NSURLErrorDomain)
    self._nsError = error
  }

  public static var _nsErrorDomain: String { return NSURLErrorDomain }

  @objc public enum Code : Int, _ErrorCodeProtocol {
    public typealias _ErrorType = URLError

    case unknown = -1
    case cancelled = -999
    case badURL = -1000
    case timedOut = -1001
    case unsupportedURL = -1002
    case cannotFindHost = -1003
    case cannotConnectToHost = -1004
    case networkConnectionLost = -1005
    case dnsLookupFailed = -1006
    case httpTooManyRedirects = -1007
    case resourceUnavailable = -1008
    case notConnectedToInternet = -1009
    case redirectToNonExistentLocation = -1010
    case badServerResponse = -1011
    case userCancelledAuthentication = -1012
    case userAuthenticationRequired = -1013
    case zeroByteResource = -1014
    case cannotDecodeRawData = -1015
    case cannotDecodeContentData = -1016
    case cannotParseResponse = -1017
    case fileDoesNotExist = -1100
    case fileIsDirectory = -1101
    case noPermissionsToReadFile = -1102
    case secureConnectionFailed = -1200
    case serverCertificateHasBadDate = -1201
    case serverCertificateUntrusted = -1202
    case serverCertificateHasUnknownRoot = -1203
    case serverCertificateNotYetValid = -1204
    case clientCertificateRejected = -1205
    case clientCertificateRequired = -1206
    case cannotLoadFromNetwork = -2000
    case cannotCreateFile = -3000
    case cannotOpenFile = -3001
    case cannotCloseFile = -3002
    case cannotWriteToFile = -3003
    case cannotRemoveFile = -3004
    case cannotMoveFile = -3005
    case downloadDecodingFailedMidStream = -3006
    case downloadDecodingFailedToComplete = -3007

    @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
    case internationalRoamingOff = -1018

    @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
    case callIsActive = -1019

    @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
    case dataNotAllowed = -1020

    @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
    case requestBodyStreamExhausted = -1021

    @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
    static var backgroundSessionRequiresSharedContainer: Code {
      return Code(rawValue: -995)!
    }

    @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
    static var backgroundSessionInUseByAnotherProcess: Code {
      return Code(rawValue: -996)!
    }

    @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
    static var backgroundSessionWasDisconnected: Code {
      return Code(rawValue: -997)!
    }
  }
}

public extension URLError {
  private var _userInfo: [NSObject : AnyObject] {
    return (self as NSError).userInfo
  }

  /// The URL which caused a load to fail.
  public var failingURL: URL? {
    return _userInfo[NSURLErrorFailingURLErrorKey] as? URL
  }

  /// The string for the URL which caused a load to fail. 
  public var failureURLString: String? {
    return _userInfo[NSURLErrorFailingURLStringErrorKey] as? String
  }

  /// The state of a failed SSL handshake.
  public var failureURLPeerTrust: SecTrust? {
    if let secTrust = _userInfo[NSURLErrorFailingURLPeerTrustErrorKey] {
      return (secTrust as! SecTrust)
    }

    return nil
  }
}

public extension URLError {
  public static var unknown: URLError.Code {
    return .unknown
  }

  public static var cancelled: URLError.Code {
    return .cancelled
  }

  public static var badURL: URLError.Code {
    return .badURL
  }

  public static var timedOut: URLError.Code {
    return .timedOut
  }

  public static var unsupportedURL: URLError.Code {
    return .unsupportedURL
  }

  public static var cannotFindHost: URLError.Code {
    return .cannotFindHost
  }

  public static var cannotConnectToHost: URLError.Code {
    return .cannotConnectToHost
  }

  public static var networkConnectionLost: URLError.Code {
    return .networkConnectionLost
  }

  public static var dnsLookupFailed: URLError.Code {
    return .dnsLookupFailed
  }

  public static var httpTooManyRedirects: URLError.Code {
    return .httpTooManyRedirects
  }

  public static var resourceUnavailable: URLError.Code {
    return .resourceUnavailable
  }

  public static var notConnectedToInternet: URLError.Code {
    return .notConnectedToInternet
  }

  public static var redirectToNonExistentLocation: URLError.Code {
    return .redirectToNonExistentLocation
  }

  public static var badServerResponse: URLError.Code {
    return .badServerResponse
  }

  public static var userCancelledAuthentication: URLError.Code {
    return .userCancelledAuthentication
  }

  public static var userAuthenticationRequired: URLError.Code {
    return .userAuthenticationRequired
  }

  public static var zeroByteResource: URLError.Code {
    return .zeroByteResource
  }

  public static var cannotDecodeRawData: URLError.Code {
    return .cannotDecodeRawData
  }

  public static var cannotDecodeContentData: URLError.Code {
    return .cannotDecodeContentData
  }

  public static var cannotParseResponse: URLError.Code {
    return .cannotParseResponse
  }

  public static var fileDoesNotExist: URLError.Code {
    return .fileDoesNotExist
  }

  public static var fileIsDirectory: URLError.Code {
    return .fileIsDirectory
  }

  public static var noPermissionsToReadFile: URLError.Code {
    return .noPermissionsToReadFile
  }

  public static var secureConnectionFailed: URLError.Code {
    return .secureConnectionFailed
  }

  public static var serverCertificateHasBadDate: URLError.Code {
    return .serverCertificateHasBadDate
  }

  public static var serverCertificateUntrusted: URLError.Code {
    return .serverCertificateUntrusted
  }

  public static var serverCertificateHasUnknownRoot: URLError.Code {
    return .serverCertificateHasUnknownRoot
  }

  public static var serverCertificateNotYetValid: URLError.Code {
    return .serverCertificateNotYetValid
  }

  public static var clientCertificateRejected: URLError.Code {
    return .clientCertificateRejected
  }

  public static var clientCertificateRequired: URLError.Code {
    return .clientCertificateRequired
  }

  public static var cannotLoadFromNetwork: URLError.Code {
    return .cannotLoadFromNetwork
  }

  public static var cannotCreateFile: URLError.Code {
    return .cannotCreateFile
  }

  public static var cannotOpenFile: URLError.Code {
    return .cannotOpenFile
  }

  public static var cannotCloseFile: URLError.Code {
    return .cannotCloseFile
  }

  public static var cannotWriteToFile: URLError.Code {
    return .cannotWriteToFile
  }

  public static var cannotRemoveFile: URLError.Code {
    return .cannotRemoveFile
  }

  public static var cannotMoveFile: URLError.Code {
    return .cannotMoveFile
  }

  public static var downloadDecodingFailedMidStream: URLError.Code {
    return .downloadDecodingFailedMidStream
  }

  public static var downloadDecodingFailedToComplete: URLError.Code {
    return .downloadDecodingFailedToComplete
  }

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
  public static var internationalRoamingOff: URLError.Code {
    return .internationalRoamingOff
  }

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
  public static var callIsActive: URLError.Code {
    return .callIsActive
  }

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
  public static var dataNotAllowed: URLError.Code {
    return .dataNotAllowed
  }

  @available(OSX, introduced: 10.7) @available(iOS, introduced: 3.0)
  public static var requestBodyStreamExhausted: URLError.Code {
    return .requestBodyStreamExhausted
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var backgroundSessionRequiresSharedContainer: Code {
    return .backgroundSessionRequiresSharedContainer
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var backgroundSessionInUseByAnotherProcess: Code {
    return .backgroundSessionInUseByAnotherProcess
  }

  @available(OSX, introduced: 10.10) @available(iOS, introduced: 8.0)
  public static var backgroundSessionWasDisconnected: Code {
    return .backgroundSessionWasDisconnected
  }
}

extension URLError {
  @available(*, unavailable, renamed: "unknown")
  public static var Unknown: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cancelled")
  public static var Cancelled: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "badURL")
  public static var BadURL: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "timedOut")
  public static var TimedOut: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "unsupportedURL")
  public static var UnsupportedURL: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotFindHost")
  public static var CannotFindHost: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotConnectToHost")
  public static var CannotConnectToHost: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "networkConnectionLost")
  public static var NetworkConnectionLost: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "dnsLookupFailed")
  public static var DNSLookupFailed: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "httpTooManyRedirects")
  public static var HTTPTooManyRedirects: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "resourceUnavailable")
  public static var ResourceUnavailable: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "notConnectedToInternet")
  public static var NotConnectedToInternet: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "redirectToNonExistentLocation")
  public static var RedirectToNonExistentLocation: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "badServerResponse")
  public static var BadServerResponse: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userCancelledAuthentication")
  public static var UserCancelledAuthentication: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "userAuthenticationRequired")
  public static var UserAuthenticationRequired: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "zeroByteResource")
  public static var ZeroByteResource: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotDecodeRawData")
  public static var CannotDecodeRawData: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotDecodeContentData")
  public static var CannotDecodeContentData: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotParseResponse")
  public static var CannotParseResponse: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileDoesNotExist")
  public static var FileDoesNotExist: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "fileIsDirectory")
  public static var FileIsDirectory: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "noPermissionsToReadFile")
  public static var NoPermissionsToReadFile: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "secureConnectionFailed")
  public static var SecureConnectionFailed: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "serverCertificateHasBadDate")
  public static var ServerCertificateHasBadDate: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "serverCertificateUntrusted")
  public static var ServerCertificateUntrusted: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "serverCertificateHasUnknownRoot")
  public static var ServerCertificateHasUnknownRoot: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "serverCertificateNotYetValid")
  public static var ServerCertificateNotYetValid: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "clientCertificateRejected")
  public static var ClientCertificateRejected: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "clientCertificateRequired")
  public static var ClientCertificateRequired: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotLoadFromNetwork")
  public static var CannotLoadFromNetwork: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotCreateFile")
  public static var CannotCreateFile: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotOpenFile")
  public static var CannotOpenFile: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotCloseFile")
  public static var CannotCloseFile: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotWriteToFile")
  public static var CannotWriteToFile: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotRemoveFile")
  public static var CannotRemoveFile: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "cannotMoveFile")
  public static var CannotMoveFile: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "downloadDecodingFailedMidStream")
  public static var DownloadDecodingFailedMidStream: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "downloadDecodingFailedToComplete")
  public static var DownloadDecodingFailedToComplete: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "internationalRoamingOff")
  public static var InternationalRoamingOff: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "callIsActive")
  public static var CallIsActive: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "dataNotAllowed")
  public static var DataNotAllowed: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "requestBodyStreamExhausted")
  public static var RequestBodyStreamExhausted: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "backgroundSessionRequiresSharedContainer")
  public static var BackgroundSessionRequiresSharedContainer: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "backgroundSessionInUseByAnotherProcess")
  public static var BackgroundSessionInUseByAnotherProcess: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }

  @available(*, unavailable, renamed: "backgroundSessionWasDisconnected")
  public static var BackgroundSessionWasDisconnected: URLError.Code {
    fatalError("unavailable accessor can't be called")
  }
}

/// Describes an error in the POSIX error domain.
public struct POSIXError : _BridgedStoredNSError {
  public let _nsError: NSError

  public init(_nsError error: NSError) {
    precondition(error.domain == NSPOSIXErrorDomain)
    self._nsError = error
  }

  public static var _nsErrorDomain: String { return NSPOSIXErrorDomain }

  public typealias Code = POSIXErrorCode
}

extension POSIXErrorCode : _ErrorCodeProtocol {
  public typealias _ErrorType = POSIXError
}

extension POSIXError {
  public static var EPERM: POSIXErrorCode {
    return .EPERM
  }

  /// No such file or directory.
  public static var ENOENT: POSIXErrorCode {
    return .ENOENT
  }

  /// No such process.
  public static var ESRCH: POSIXErrorCode {
    return .ESRCH
  }

  /// Interrupted system call.
  public static var EINTR: POSIXErrorCode {
    return .EINTR
  }

  /// Input/output error.
  public static var EIO: POSIXErrorCode {
    return .EIO
  }

  /// Device not configured.
  public static var ENXIO: POSIXErrorCode {
    return .ENXIO
  }

  /// Argument list too long.
  public static var E2BIG: POSIXErrorCode {
    return .E2BIG
  }

  /// Exec format error.
  public static var ENOEXEC: POSIXErrorCode {
    return .ENOEXEC
  }

  /// Bad file descriptor.
  public static var EBADF: POSIXErrorCode {
    return .EBADF
  }

  /// No child processes.
  public static var ECHILD: POSIXErrorCode {
    return .ECHILD
  }

  /// Resource deadlock avoided.
  public static var EDEADLK: POSIXErrorCode {
    return .EDEADLK
  }

  /// Cannot allocate memory.
  public static var ENOMEM: POSIXErrorCode {
    return .ENOMEM
  }

  /// Permission denied.
  public static var EACCES: POSIXErrorCode {
    return .EACCES
  }

  /// Bad address.
  public static var EFAULT: POSIXErrorCode {
    return .EFAULT
  }

  /// Block device required.
  public static var ENOTBLK: POSIXErrorCode {
    return .ENOTBLK
  }
  /// Device / Resource busy.
  public static var EBUSY: POSIXErrorCode {
    return .EBUSY
  }
  /// File exists.
  public static var EEXIST: POSIXErrorCode {
    return .EEXIST
  }
  /// Cross-device link.
  public static var EXDEV: POSIXErrorCode {
    return .EXDEV
  }
  /// Operation not supported by device.
  public static var ENODEV: POSIXErrorCode {
    return .ENODEV
  }
  /// Not a directory.
  public static var ENOTDIR: POSIXErrorCode {
    return .ENOTDIR
  }
  /// Is a directory.
  public static var EISDIR: POSIXErrorCode {
    return .EISDIR
  }
  /// Invalid argument.
  public static var EINVAL: POSIXErrorCode {
    return .EINVAL
  }
  /// Too many open files in system.
  public static var ENFILE: POSIXErrorCode {
    return .ENFILE
  }
  /// Too many open files.
  public static var EMFILE: POSIXErrorCode {
    return .EMFILE
  }
  /// Inappropriate ioctl for device.
  public static var ENOTTY: POSIXErrorCode {
    return .ENOTTY
  }
  /// Text file busy.
  public static var ETXTBSY: POSIXErrorCode {
    return .ETXTBSY
  }
  /// File too large.
  public static var EFBIG: POSIXErrorCode {
    return .EFBIG
  }
  /// No space left on device.
  public static var ENOSPC: POSIXErrorCode {
    return .ENOSPC
  }
  /// Illegal seek.
  public static var ESPIPE: POSIXErrorCode {
    return .ESPIPE
  }
  /// Read-only file system.
  public static var EROFS: POSIXErrorCode {
    return .EROFS
  }
  /// Too many links.
  public static var EMLINK: POSIXErrorCode {
    return .EMLINK
  }
  /// Broken pipe.
  public static var EPIPE: POSIXErrorCode {
    return .EPIPE
  }

/// math software.
  /// Numerical argument out of domain.
  public static var EDOM: POSIXErrorCode {
    return .EDOM
  }
  /// Result too large.
  public static var ERANGE: POSIXErrorCode {
    return .ERANGE
  }

/// non-blocking and interrupt i/o.
  /// Resource temporarily unavailable.
  public static var EAGAIN: POSIXErrorCode {
    return .EAGAIN
  }
  /// Operation would block.
  public static var EWOULDBLOCK: POSIXErrorCode {
    return .EWOULDBLOCK
  }
  /// Operation now in progress.
  public static var EINPROGRESS: POSIXErrorCode {
    return .EINPROGRESS
  }
  /// Operation already in progress.
  public static var EALREADY: POSIXErrorCode {
    return .EALREADY
  }

/// ipc/network software -- argument errors.
  /// Socket operation on non-socket.
  public static var ENOTSOCK: POSIXErrorCode {
    return .ENOTSOCK
  }
  /// Destination address required.
  public static var EDESTADDRREQ: POSIXErrorCode {
    return .EDESTADDRREQ
  }
  /// Message too long.
  public static var EMSGSIZE: POSIXErrorCode {
    return .EMSGSIZE
  }
  /// Protocol wrong type for socket.
  public static var EPROTOTYPE: POSIXErrorCode {
    return .EPROTOTYPE
  }
  /// Protocol not available.
  public static var ENOPROTOOPT: POSIXErrorCode {
    return .ENOPROTOOPT
  }
  /// Protocol not supported.
  public static var EPROTONOSUPPORT: POSIXErrorCode {
    return .EPROTONOSUPPORT
  }
  /// Socket type not supported.
  public static var ESOCKTNOSUPPORT: POSIXErrorCode {
    return .ESOCKTNOSUPPORT
  }
  /// Operation not supported.
  public static var ENOTSUP: POSIXErrorCode {
    return .ENOTSUP
  }
  /// Protocol family not supported.
  public static var EPFNOSUPPORT: POSIXErrorCode {
    return .EPFNOSUPPORT
  }
  /// Address family not supported by protocol family.
  public static var EAFNOSUPPORT: POSIXErrorCode {
    return .EAFNOSUPPORT
  }

  /// Address already in use.
  public static var EADDRINUSE: POSIXErrorCode {
    return .EADDRINUSE
  }
  /// Can't assign requested address.
  public static var EADDRNOTAVAIL: POSIXErrorCode {
    return .EADDRNOTAVAIL
  }

/// ipc/network software -- operational errors
  /// Network is down.
  public static var ENETDOWN: POSIXErrorCode {
    return .ENETDOWN
  }
  /// Network is unreachable.
  public static var ENETUNREACH: POSIXErrorCode {
    return .ENETUNREACH
  }
  /// Network dropped connection on reset.
  public static var ENETRESET: POSIXErrorCode {
    return .ENETRESET
  }
  /// Software caused connection abort.
  public static var ECONNABORTED: POSIXErrorCode {
    return .ECONNABORTED
  }
  /// Connection reset by peer.
  public static var ECONNRESET: POSIXErrorCode {
    return .ECONNRESET
  }
  /// No buffer space available.
  public static var ENOBUFS: POSIXErrorCode {
    return .ENOBUFS
  }
  /// Socket is already connected.
  public static var EISCONN: POSIXErrorCode {
    return .EISCONN
  }
  /// Socket is not connected.
  public static var ENOTCONN: POSIXErrorCode {
    return .ENOTCONN
  }
  /// Can't send after socket shutdown.
  public static var ESHUTDOWN: POSIXErrorCode {
    return .ESHUTDOWN
  }
  /// Too many references: can't splice.
  public static var ETOOMANYREFS: POSIXErrorCode {
    return .ETOOMANYREFS
  }
  /// Operation timed out.
  public static var ETIMEDOUT: POSIXErrorCode {
    return .ETIMEDOUT
  }
  /// Connection refused.
  public static var ECONNREFUSED: POSIXErrorCode {
    return .ECONNREFUSED
  }

  /// Too many levels of symbolic links.
  public static var ELOOP: POSIXErrorCode {
    return .ELOOP
  }
  /// File name too long.
  public static var ENAMETOOLONG: POSIXErrorCode {
    return .ENAMETOOLONG
  }

  /// Host is down.
  public static var EHOSTDOWN: POSIXErrorCode {
    return .EHOSTDOWN
  }
  /// No route to host.
  public static var EHOSTUNREACH: POSIXErrorCode {
    return .EHOSTUNREACH
  }
  /// Directory not empty.
  public static var ENOTEMPTY: POSIXErrorCode {
    return .ENOTEMPTY
  }

/// quotas & mush.
  /// Too many processes.
  public static var EPROCLIM: POSIXErrorCode {
    return .EPROCLIM
  }
  /// Too many users.
  public static var EUSERS: POSIXErrorCode {
    return .EUSERS
  }
  /// Disc quota exceeded.
  public static var EDQUOT: POSIXErrorCode {
    return .EDQUOT
  }

/// Network File System.
  /// Stale NFS file handle.
  public static var ESTALE: POSIXErrorCode {
    return .ESTALE
  }
  /// Too many levels of remote in path.
  public static var EREMOTE: POSIXErrorCode {
    return .EREMOTE
  }
  /// RPC struct is bad.
  public static var EBADRPC: POSIXErrorCode {
    return .EBADRPC
  }
  /// RPC version wrong.
  public static var ERPCMISMATCH: POSIXErrorCode {
    return .ERPCMISMATCH
  }
  /// RPC prog. not avail.
  public static var EPROGUNAVAIL: POSIXErrorCode {
    return .EPROGUNAVAIL
  }
  /// Program version wrong.
  public static var EPROGMISMATCH: POSIXErrorCode {
    return .EPROGMISMATCH
  }
  /// Bad procedure for program.
  public static var EPROCUNAVAIL: POSIXErrorCode {
    return .EPROCUNAVAIL
  }

  /// No locks available.
  public static var ENOLCK: POSIXErrorCode {
    return .ENOLCK
  }
  /// Function not implemented.
  public static var ENOSYS: POSIXErrorCode {
    return .ENOSYS
  }

  /// Inappropriate file type or format.
  public static var EFTYPE: POSIXErrorCode {
    return .EFTYPE
  }
  /// Authentication error.
  public static var EAUTH: POSIXErrorCode {
    return .EAUTH
  }
  /// Need authenticator.
  public static var ENEEDAUTH: POSIXErrorCode {
    return .ENEEDAUTH
  }

/// Intelligent device errors.
  /// Device power is off.
  public static var EPWROFF: POSIXErrorCode {
    return .EPWROFF
  }
  /// Device error, e.g. paper out.
  public static var EDEVERR: POSIXErrorCode {
    return .EDEVERR
  }

  /// Value too large to be stored in data type.
  public static var EOVERFLOW: POSIXErrorCode {
    return .EOVERFLOW
  }

/// Program loading errors.
  /// Bad executable.
  public static var EBADEXEC: POSIXErrorCode {
    return .EBADEXEC
  }
  /// Bad CPU type in executable.
  public static var EBADARCH: POSIXErrorCode {
    return .EBADARCH
  }
  /// Shared library version mismatch.
  public static var ESHLIBVERS: POSIXErrorCode {
    return .ESHLIBVERS
  }
  /// Malformed Macho file.
  public static var EBADMACHO: POSIXErrorCode {
    return .EBADMACHO
  }

  /// Operation canceled.
  public static var ECANCELED: POSIXErrorCode {
    return .ECANCELED
  }

  /// Identifier removed.
  public static var EIDRM: POSIXErrorCode {
    return .EIDRM
  }
  /// No message of desired type.
  public static var ENOMSG: POSIXErrorCode {
    return .ENOMSG
  }
  /// Illegal byte sequence.
  public static var EILSEQ: POSIXErrorCode {
    return .EILSEQ
  }
  /// Attribute not found.
  public static var ENOATTR: POSIXErrorCode {
    return .ENOATTR
  }

  /// Bad message.
  public static var EBADMSG: POSIXErrorCode {
    return .EBADMSG
  }
  /// Reserved.
  public static var EMULTIHOP: POSIXErrorCode {
    return .EMULTIHOP
  }
  /// No message available on STREAM.
  public static var ENODATA: POSIXErrorCode {
    return .ENODATA
  }
  /// Reserved.
  public static var ENOLINK: POSIXErrorCode {
    return .ENOLINK
  }
  /// No STREAM resources.
  public static var ENOSR: POSIXErrorCode {
    return .ENOSR
  }
  /// Not a STREAM.
  public static var ENOSTR: POSIXErrorCode {
    return .ENOSTR
  }
  /// Protocol error.
  public static var EPROTO: POSIXErrorCode {
    return .EPROTO
  }
  /// STREAM ioctl timeout.
  public static var ETIME: POSIXErrorCode {
    return .ETIME
  }

  /// No such policy registered.
  public static var ENOPOLICY: POSIXErrorCode {
    return .ENOPOLICY
  }

  /// State not recoverable.
  public static var ENOTRECOVERABLE: POSIXErrorCode {
    return .ENOTRECOVERABLE
  }
  /// Previous owner died.
  public static var EOWNERDEAD: POSIXErrorCode {
    return .EOWNERDEAD
  }

  /// Interface output queue is full.
  public static var EQFULL: POSIXErrorCode {
    return .EQFULL
  }
}

/// Describes an error in the Mach error domain.
public struct MachError : _BridgedStoredNSError {
  public let _nsError: NSError

  public init(_nsError error: NSError) {
    precondition(error.domain == NSMachErrorDomain)
    self._nsError = error
  }

  public static var _nsErrorDomain: String { return NSMachErrorDomain }

  public typealias Code = MachErrorCode
}

extension MachErrorCode : _ErrorCodeProtocol {
  public typealias _ErrorType = MachError
}

extension MachError {
  public static var success: MachError.Code {
    return .success
  }

  /// Specified address is not currently valid.
  public static var invalidAddress: MachError.Code {
    return .invalidAddress
  }

  /// Specified memory is valid, but does not permit the required
  /// forms of access.
  public static var protectionFailure: MachError.Code {
    return .protectionFailure
  }

  /// The address range specified is already in use, or no address
  /// range of the size specified could be found.  
  public static var noSpace: MachError.Code {
    return .noSpace
  }

  /// The function requested was not applicable to this type of
  /// argument, or an argument is invalid.
  public static var invalidArgument: MachError.Code {
    return .invalidArgument
  }

  /// The function could not be performed.  A catch-all.
  public static var failure: MachError.Code {
    return .failure
  }

  /// A system resource could not be allocated to fulfill this
  /// request.  This failure may not be permanent.
  public static var resourceShortage: MachError.Code {
    return .resourceShortage
  }

  /// The task in question does not hold receive rights for the port
  /// argument.
  public static var notReceiver: MachError.Code {
    return .notReceiver
  }

  /// Bogus access restriction.
  public static var noAccess: MachError.Code {
    return .noAccess
  }

  /// During a page fault, the target address refers to a memory
  /// object that has been destroyed.  This failure is permanent.
  public static var memoryFailure: MachError.Code {
    return .memoryFailure
  }

  /// During a page fault, the memory object indicated that the data
  /// could not be returned.  This failure may be temporary; future
  /// attempts to access this same data may succeed, as defined by the
  /// memory object.
  public static var memoryError: MachError.Code {
    return .memoryError
  }

  /// The receive right is already a member of the portset.
  public static var alreadyInSet: MachError.Code {
    return .alreadyInSet
  }

  /// The receive right is not a member of a port set.
  public static var notInSet: MachError.Code {
    return .notInSet
  }

  /// The name already denotes a right in the task.
  public static var nameExists: MachError.Code {
    return .nameExists
  }

  /// The operation was aborted.  Ipc code will catch this and reflect
  /// it as a message error.
  public static var aborted: MachError.Code {
    return .aborted
  }

  /// The name doesn't denote a right in the task.
  public static var invalidName: MachError.Code {
    return .invalidName
  }

  /// Target task isn't an active task.
  public static var invalidTask: MachError.Code {
    return .invalidTask
  }

  /// The name denotes a right, but not an appropriate right.
  public static var invalidRight: MachError.Code {
    return .invalidRight
  }

  /// A blatant range error.
  public static var invalidValue: MachError.Code {
    return .invalidValue
  }

  /// Operation would overflow limit on user-references.
  public static var userReferencesOverflow: MachError.Code {
    return .userReferencesOverflow
  }

  /// The supplied (port) capability is improper.
  public static var invalidCapability: MachError.Code {
    return .invalidCapability
  }

  /// The task already has send or receive rights for the port under
  /// another name.
  public static var rightExists: MachError.Code {
    return .rightExists
  }

  /// Target host isn't actually a host.
  public static var invalidHost: MachError.Code {
    return .invalidHost
  }

  /// An attempt was made to supply "precious" data for memory that is
  /// already present in a memory object.
  public static var memoryPresent: MachError.Code {
    return .memoryPresent
  }

  /// A page was requested of a memory manager via
  /// memory_object_data_request for an object using a
  /// MEMORY_OBJECT_COPY_CALL strategy, with the VM_PROT_WANTS_COPY
  /// flag being used to specify that the page desired is for a copy
  /// of the object, and the memory manager has detected the page was
  /// pushed into a copy of the object while the kernel was walking
  /// the shadow chain from the copy to the object. This error code is
  /// delivered via memory_object_data_error and is handled by the
  /// kernel (it forces the kernel to restart the fault). It will not
  /// be seen by users.
  public static var memoryDataMoved: MachError.Code {
    return .memoryDataMoved
  }

  /// A strategic copy was attempted of an object upon which a quicker
  /// copy is now possible.  The caller should retry the copy using
  /// vm_object_copy_quickly. This error code is seen only by the
  /// kernel.
  public static var memoryRestartCopy: MachError.Code {
    return .memoryRestartCopy
  }

  /// An argument applied to assert processor set privilege was not a
  /// processor set control port.
  public static var invalidProcessorSet: MachError.Code {
    return .invalidProcessorSet
  }

  /// The specified scheduling attributes exceed the thread's limits.
  public static var policyLimit: MachError.Code {
    return .policyLimit
  }

  /// The specified scheduling policy is not currently enabled for the
  /// processor set.
  public static var invalidPolicy: MachError.Code {
    return .invalidPolicy
  }

  /// The external memory manager failed to initialize the memory object.
  public static var invalidObject: MachError.Code {
    return .invalidObject
  }

  /// A thread is attempting to wait for an event for which there is
  /// already a waiting thread.
  public static var alreadyWaiting: MachError.Code {
    return .alreadyWaiting
  }

  /// An attempt was made to destroy the default processor set.
  public static var defaultSet: MachError.Code {
    return .defaultSet
  }

  /// An attempt was made to fetch an exception port that is
  /// protected, or to abort a thread while processing a protected
  /// exception.
  public static var exceptionProtected: MachError.Code {
    return .exceptionProtected
  }

  /// A ledger was required but not supplied.
  public static var invalidLedger: MachError.Code {
    return .invalidLedger
  }

  /// The port was not a memory cache control port.
  public static var invalidMemoryControl: MachError.Code {
    return .invalidMemoryControl
  }

  /// An argument supplied to assert security privilege was not a host
  /// security port.
  public static var invalidSecurity: MachError.Code {
    return .invalidSecurity
  }

  /// thread_depress_abort was called on a thread which was not
  /// currently depressed.
  public static var notDepressed: MachError.Code {
    return .notDepressed
  }

  /// Object has been terminated and is no longer available.
  public static var terminated: MachError.Code {
    return .terminated
  }

  /// Lock set has been destroyed and is no longer available.
  public static var lockSetDestroyed: MachError.Code {
    return .lockSetDestroyed
  }

  /// The thread holding the lock terminated before releasing the lock.
  public static var lockUnstable: MachError.Code {
    return .lockUnstable
  }

  /// The lock is already owned by another thread.
  public static var lockOwned: MachError.Code {
    return .lockOwned
  }

  /// The lock is already owned by the calling thread.
  public static var lockOwnedSelf: MachError.Code {
    return .lockOwnedSelf
  }

  /// Semaphore has been destroyed and is no longer available.
  public static var semaphoreDestroyed: MachError.Code {
    return .semaphoreDestroyed
  }

  /// Return from RPC indicating the target server was terminated
  /// before it successfully replied.
  public static var rpcServerTerminated: MachError.Code {
    return .rpcServerTerminated
  }

  /// Terminate an orphaned activation.
  public static var rpcTerminateOrphan: MachError.Code {
    return .rpcTerminateOrphan
  }

  /// Allow an orphaned activation to continue executing.
  public static var rpcContinueOrphan: MachError.Code {
    return .rpcContinueOrphan
  }

  /// Empty thread activation (No thread linked to it).
  public static var notSupported: MachError.Code {
    return .notSupported
  }

  /// Remote node down or inaccessible.
  public static var nodeDown: MachError.Code {
    return .nodeDown
  }

  /// A signalled thread was not actually waiting.
  public static var notWaiting: MachError.Code {
    return .notWaiting
  }

  /// Some thread-oriented operation (semaphore_wait) timed out.
  public static var operationTimedOut: MachError.Code {
    return .operationTimedOut
  }

  /// During a page fault, indicates that the page was rejected as a
  /// result of a signature check.
  public static var codesignError: MachError.Code {
    return .codesignError
  }

  /// The requested property cannot be changed at this time.
  public static var policyStatic: MachError.Code {
    return .policyStatic
  }
}

public struct ErrorUserInfoKey : RawRepresentable, _SwiftNewtypeWrapper, Equatable, Hashable, _ObjectiveCBridgeable {
  public init(rawValue: String) { self.rawValue = rawValue }
  public var rawValue: String
}

public extension ErrorUserInfoKey {
  @available(*, deprecated, renamed: "NSUnderlyingErrorKey")
  static let underlyingErrorKey = ErrorUserInfoKey(rawValue: NSUnderlyingErrorKey)

  @available(*, deprecated, renamed: "NSLocalizedDescriptionKey")
  static let localizedDescriptionKey = ErrorUserInfoKey(rawValue: NSLocalizedDescriptionKey)

  @available(*, deprecated, renamed: "NSLocalizedFailureReasonErrorKey")
  static let localizedFailureReasonErrorKey = ErrorUserInfoKey(rawValue: NSLocalizedFailureReasonErrorKey)

  @available(*, deprecated, renamed: "NSLocalizedRecoverySuggestionErrorKey")
  static let localizedRecoverySuggestionErrorKey = ErrorUserInfoKey(rawValue: NSLocalizedRecoverySuggestionErrorKey)

  @available(*, deprecated, renamed: "NSLocalizedRecoveryOptionsErrorKey")
  static let localizedRecoveryOptionsErrorKey = ErrorUserInfoKey(rawValue: NSLocalizedRecoveryOptionsErrorKey)

  @available(*, deprecated, renamed: "NSRecoveryAttempterErrorKey")
  static let recoveryAttempterErrorKey = ErrorUserInfoKey(rawValue: NSRecoveryAttempterErrorKey)

  @available(*, deprecated, renamed: "NSHelpAnchorErrorKey")
  static let helpAnchorErrorKey = ErrorUserInfoKey(rawValue: NSHelpAnchorErrorKey)

  @available(*, deprecated, renamed: "NSStringEncodingErrorKey")
  static let stringEncodingErrorKey = ErrorUserInfoKey(rawValue: NSStringEncodingErrorKey)

  @available(*, deprecated, renamed: "NSURLErrorKey")
  static let NSURLErrorKey = ErrorUserInfoKey(rawValue: Foundation.NSURLErrorKey)

  @available(*, deprecated, renamed: "NSFilePathErrorKey")
  static let filePathErrorKey = ErrorUserInfoKey(rawValue: NSFilePathErrorKey)
}
