//
//  NavigationUIKitProxy.swift
//  ReducerArchitecture
//
//  Created by Ilya Belenkiy on 11/4/25.
//

#if canImport(UIKit)
import UIKit

class UIKitNavigationProxy: NavigationProxy {
    static func hostingVC<T: ViewModelUIContainer>(_ viewModelUI: T) -> UIViewController {
        HostingController<T>(viewModel: viewModelUI.viewModel)
    }

    private var nc: UINavigationController

    init(_ nc: UINavigationController) {
        self.nc = nc
    }

    var currentIndex: Int {
        nc.viewControllers.count - 1
    }

    func push<Nsp: ViewModelUINamespace>(_ viewModelUI: ViewModelUI<Nsp>) -> Int {
        let vc = Self.hostingVC(viewModelUI)
        nc.pushViewController(vc, animated: true)
        return nc.viewControllers.count - 1
    }

    func replaceTop<Nsp: ViewModelUINamespace>(with viewModelUI: ViewModelUI<Nsp>) -> Int {
        guard !nc.viewControllers.isEmpty else { return -1 }
        let vc = Self.hostingVC(viewModelUI)
        nc.viewControllers[nc.viewControllers.count - 1] = vc
        return nc.viewControllers.count - 1
    }

    func popTo(_ index: Int) {
        let vc = nc.viewControllers[index]
        nc.popToViewController(vc, animated: true)
    }
}

#endif


