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

    isolated deinit { publishedValue.finish() }
}
