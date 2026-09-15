//
//  BaseViewModel.swift
//  Example
//
//  Created by Ilya Belenkiy on 11/21/25.
//

import Foundation

open class BaseViewModel<T: Sendable>: BasicViewModel {
   public typealias PublishedValue = T

   public let id: UUID = .init()

   public var isCancelled = false
   public var publishedValue: PublishedValues<T> = .init()
   public var children: [String : any AsyncNavigation.BasicViewModel] = [:]

   open func cancel() {
      isCancelled = true
      _cancel()
   }

    public init() {}

#if compiler(<6.4)
    // Avoid the generic isolated-deinit optimizer crash: https://github.com/swiftlang/swift/issues/87462
    @_optimize(none)
#endif
    isolated deinit { publishedValue.finish() }
}
