//
//  BaseViewModel.swift
//  Example
//
//  Created by Ilya Belenkiy on 11/21/25.
//

import Foundation
import Combine
import CombineEx

open class BaseViewModel<T>: BasicViewModel {
   public typealias PublishedValue = T

   public let id: UUID = .init()

   public var isCancelled = false
   public var hasRequest = false
   public var publishedValue: PassthroughSubject<T, Cancel> = .init()
   public var children: [String : any AsyncNavigation.BasicViewModel] = [:]

   open func cancel() {
      isCancelled = true
      _cancel()
   }

    public init() {}
}
