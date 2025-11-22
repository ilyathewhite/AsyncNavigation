//
//  NavigationProxy.swift
//  ReducerArchitecture
//
//  Created by Ilya Belenkiy on 11/3/25.
//

import Combine

@MainActor
public protocol NavigationProxy {
    /// Returns the index of the top component on the stack.
    var currentIndex: Int { get }

    /// Pushes the next UI component on the navigation stack.
    /// Returns the index of the pushed component on the navigation stack.
    func push<Nsp: ViewModelUINamespace>(_ viewModelUI: ViewModelUI<Nsp>) -> Int

    /// Replaces the last UI component on the navigation stack.
    /// Returns the index of the pushed component on the navigation stack.
    func replaceTop<Nsp: ViewModelUINamespace>(with viewModelUI: ViewModelUI<Nsp>) -> Int

    /// Pops the navigation stack to the component at `index`.
    func pop(to index: Int) -> Void
}

@MainActor
public extension NavigationProxy {
    func pop() {
        pop(to: currentIndex - 1)
    }

    func popToRoot() {
        pop(to: -1)
    }
}
