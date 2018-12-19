//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//


@testable import Wire
import XCTest
import SnapshotTesting

extension UITableViewCell: UITableViewDelegate, UITableViewDataSource {
	@objc public func wrapInTableView() -> UITableView {
		let tableView = UITableView(frame: self.bounds, style: .plain)
		
		tableView.delegate = self
		tableView.dataSource = self
		tableView.backgroundColor = .clear
		tableView.separatorStyle = .none
		tableView.rowHeight = UITableView.automaticDimension
		tableView.layoutMargins = self.layoutMargins
		
		let size = self.systemLayoutSizeFitting(CGSize(width: bounds.width, height: 0.0) , withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
		self.layoutSubviews()
		
		self.bounds = CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height)
		self.contentView.bounds = self.bounds
		
		tableView.reloadData()
		tableView.bounds = self.bounds
		tableView.layoutIfNeeded()
		
		NSLayoutConstraint.activate([
			tableView.heightAnchor.constraint(equalToConstant: size.height)
			])
		
		self.layoutSubviews()
		return tableView
	}
	
	public func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}
	
	public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 1
	}
	
	public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		return self.bounds.size.height
	}
	
	public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		return self
	}
}

open class ZMSnapshotTestCase: XCTestCase {
	
	typealias ConfigurationWithDeviceType = (_ view: UIView, _ isPad: Bool) -> Void
	
	var uiMOC: NSManagedObjectContext!
	
	/// The color of the container view in which the view to
	/// be snapshot will be placed, defaults to UIColor.lightGrayColor
	var snapshotBackgroundColor: UIColor?
	
	/// If YES the uiMOC will have image and file caches. Defaults to NO.
	var needsCaches: Bool {
		get {
			return false
		}
	}
	
	var documentsDirectory: URL?
	
	override open func setUp() {
		super.setUp()
		
		XCTAssertEqual(UIScreen.main.scale, 2, "Snapshot tests need to be run on a device with a 2x scale")
		if UIDevice.current.systemVersion.compare("10", options: .numeric, range: nil, locale: .current) == .orderedAscending {
			XCTFail("Snapshot tests need to be run on a device running at least iOS 10")
		}
		AppRootViewController.configureAppearance()
		UIView.setAnimationsEnabled(false)
		accentColor = .vividRed
		snapshotBackgroundColor = UIColor.clear
		
		// Enable when the design of the view has changed in order to update the reference snapshots
		#if RECORDING_SNAPSHOTS
		recordMode = true
		#endif
		
		//        usesDrawViewHierarchyInRect = true
		let contextExpectation: XCTestExpectation = expectation(description: "It should create a context")
		StorageStack.reset()
		StorageStack.shared.createStorageAsInMemory = true
		do {
			documentsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		} catch {
			XCTAssertNil(error, "Unexpected error \(error)")
		}
		
		StorageStack.shared.createManagedObjectContextDirectory(accountIdentifier: UUID(),
																applicationContainer: documentsDirectory!,
																dispatchGroup: nil,
																startedMigrationCallback: nil,
																completionHandler: { contextDirectory in
																	self.uiMOC = contextDirectory.uiContext
																	contextExpectation.fulfill()
		})
		
		wait(for: [contextExpectation], timeout: 0.1)
		
		if needsCaches {
			setUpCaches()
		}
	}
	
	override open func tearDown() {
		if needsCaches {
			wipeCaches()
		}
		// Needs to be called before setting self.documentsDirectory to nil.
		removeContentsOfDocumentsDirectory()
		uiMOC = nil
		documentsDirectory = nil
		snapshotBackgroundColor = nil
		UIColor.accentOverride = .undefined
		UIView.setAnimationsEnabled(true)
		super.tearDown()
	}
	
	func removeContentsOfDocumentsDirectory() {
		do {
			let contents = try FileManager.default.contentsOfDirectory(at: documentsDirectory!, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
			
			for content: URL in contents {
				do {
					try FileManager.default.removeItem(at: content)
				} catch {
					XCTAssertNil(error, "Unexpected error \(error)")
				}
			}
			
		} catch {
			XCTAssertNil(error, "Unexpected error \(error)")
		}
		
	}
	
	func wipeCaches() {
		uiMOC.zm_fileAssetCache.wipeCaches()
		uiMOC.zm_userImageCache.wipeCache()
		PersonName.stringsToPersonNames().removeAllObjects()
	}
	
	func setUpCaches() {
		uiMOC.zm_userImageCache = UserImageLocalCache(location: nil)
		uiMOC.zm_fileAssetCache = FileAssetCache(location: nil)
	}
	
}

typealias Configuration = (_ view: UIView) -> Void

struct SnapshotConfig {
	var extraLayoutPass: Bool = false
	var deviceName: String? = nil
	var identifier: String? = nil
	var suffix: NSOrderedSet? = nil//FBSnapshotTestCaseDefaultSuffixes(),
	var tolerance: Float = 0
	var configuration: Configuration? = nil

	init(extraLayoutPass: Bool = false,
		 deviceName: String? = nil,
		 identifier: String? = nil,
		 suffix: NSOrderedSet? = nil,//FBSnapshotTestCaseDefaultSuffixes(),
		tolerance: Float = 0,
		configuration: Configuration? = nil) {
		
		self.extraLayoutPass = extraLayoutPass
		self.deviceName = deviceName
		self.identifier = identifier
		self.suffix = suffix
		self.tolerance = tolerance
		self.configuration = configuration
	}
}


// MARK: - Helpers
extension ZMSnapshotTestCase {
	func containerView(with view: UIView) -> UIView {
		let container = UIView(frame: view.bounds)
		container.backgroundColor = snapshotBackgroundColor
		container.addSubview(view)
		
		view.fitInSuperview()
		view.translatesAutoresizingMaskIntoConstraints = false
		return container
	}
	
	
	func customTestName(testName: String, snapshotConfig: SnapshotConfig) -> String {
		var customTestName = testName
		if let identifier = snapshotConfig.identifier {
			customTestName += identifier
		}
		
		if let deviceName = snapshotConfig.deviceName {
			customTestName += deviceName
		}
		
		return customTestName
	}
	
	private func snapshotVerify(view: UIView,
								snapshotConfig: SnapshotConfig,
								file: StaticString = #file,
								testName: String = #function,
								line: UInt = #line) {
		
		///TODO: more argument
		let precision: Float = 1-snapshotConfig.tolerance

		assertSnapshot(matching: view,
					   as: .image(precision: precision),
					   file: file,
					   testName: customTestName(testName: testName, snapshotConfig: snapshotConfig),
					   line: line)
		
	}
	
	private func assertAmbigousLayout(_ view: UIView,
									  file: StaticString = #file,
									  line: UInt = #line) {
		if view.hasAmbiguousLayout,
			let trace = view._autolayoutTrace() {
			let description = "Ambigous layout in view: \(view) trace: \n\(trace)"
			
			recordFailure(withDescription: description, inFile: "\(file)", atLine: Int(line), expected: true)
			
		}
	}
	
	private func assertEmptyFrame(_ view: UIView,
								  file: StaticString = #file,
								  line: UInt = #line) -> Bool {
		if view.frame.isEmpty {
			let description = "View frame can not be empty"
			let filePath = "\(file)"
			recordFailure(withDescription: description, inFile: filePath, atLine: Int(line), expected: true)
			return true
		}
		return false
	}
}

// MARK: - interfaces

extension ZMSnapshotTestCase {
	
	/// Performs an assertion with the given view and the recorded snapshot.
	func verify(view: UIView,
				snapshotConfig: SnapshotConfig = SnapshotConfig(),
				file: StaticString = #file,
				testName: String = #function,
				line: UInt = #line) {
		
		snapshotConfig.configuration?(view)
		
		if snapshotConfig.extraLayoutPass {
			RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
		}
		
		view.layer.speed = 0 // freeze animations for deterministic tests
		snapshotVerify(view: view,
					   snapshotConfig: snapshotConfig,
					   file: file,
					   testName: testName,
						line: line)
		
	}
	
	/// Performs an assertion with the given view and the recorded snapshot with the custom width
	func verifyView(view: UIView,
					width: CGFloat,
					snapshotConfig: SnapshotConfig,
		file: StaticString = #file,
		testName: String = #function,
		line: UInt = #line) {
		let container = containerView(with: view)
		
		container.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			container.widthAnchor.constraint(equalToConstant: width)
			])
		
		container.layoutIfNeeded()
		
		if assertEmptyFrame(container, file: file, line: line) {
			return
		}
		
		snapshotConfig.configuration?(view)
		
		if snapshotConfig.extraLayoutPass {
			RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
		}
		
		view.layer.speed = 0 // freeze animations for deterministic tests
		
		var snapshotConfigClone = snapshotConfig
		snapshotConfigClone.identifier = "\(Int(width))"
		
		snapshotVerify(view: container,
					   snapshotConfig: snapshotConfigClone,
			file: file,
			testName: testName,
			line: line)

	}
	
	/// Performs multiple assertions with the given view using the screen sizes of
	/// the common iPhones in Portrait and iPad in Landscape and Portrait.
	/// This method only makes sense for views that will be on presented fullscreen.
	func verifyInAllPhoneWidths(view: UIView,
								snapshotConfig: SnapshotConfig = SnapshotConfig(),
		file: StaticString = #file,
		testName: String = #function,
		line: UInt = #line) {
		assertAmbigousLayout(view, file: file, line: line)
		
		for width in phoneWidths() {
			verifyView(view: view,
					   width: width,
					   snapshotConfig: snapshotConfig,
				file: file,
				testName: testName,
				line: line)
		}
	}
	
	func verifyInAllTabletWidths(view: UIView,
								 snapshotConfig: SnapshotConfig = SnapshotConfig(),
		file: StaticString = #file,
		testName: String = #function,
		line: UInt = #line) {
		assertAmbigousLayout(view, file: file, line: line)
		for width in tabletWidths() {
			verifyView(view: view,
					   width: width,
					   snapshotConfig: snapshotConfig,
				file: file,
				testName: testName,
				line: line)

		}
	}
	
	func verifyInIPhoneSize(viewController: UIViewController,
							snapshotConfig: SnapshotConfig = SnapshotConfig(),
							file: StaticString = #file,
							testName: String = #function,
							line: UInt = #line) {
		///TODO: check the file name
		assertSnapshot(matching: viewController,
					   as: .image(on: .iPhoneSe(.portrait)),
					   file: file,
					   testName:testName,
					   line: line)
	}
	
	/// verify the snapshot with default iphone size
	///
	/// - Parameters:
	///   - view: the view to verify
	func verifyInIPhoneSize(view: UIView,
							snapshotConfig: SnapshotConfig = SnapshotConfig(),
		file: StaticString = #file,
		testName: String = #function,
		line: UInt = #line) {

		view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			view.heightAnchor.constraint(equalToConstant: defaultIPhoneSize.height),
			view.widthAnchor.constraint(equalToConstant: defaultIPhoneSize.width)
			])
		
		view.layoutIfNeeded()
		
		verify(view: view,
			   snapshotConfig: snapshotConfig,
			file: file,
			testName: testName,
			line: line)

	}
	
	func verifyInAllColorSchemes(view: UIView,
								 snapshotConfig: SnapshotConfig = SnapshotConfig(),
		file: StaticString = #file,
		testName: String = #function,
		line: UInt = #line) {
		if var themeable = view as? Themeable {
			themeable.colorSchemeVariant = .light
			snapshotBackgroundColor = .white
			
			var snapshotConfigLightTheme = snapshotConfig
			snapshotConfigLightTheme.identifier = "LightTheme"
			
			
			verify(view: view, snapshotConfig: snapshotConfigLightTheme,
				   file: file,
				   testName: testName,
				   line: line)
			themeable.colorSchemeVariant = .dark
			snapshotBackgroundColor = .black
			
			var snapshotConfigDarkTheme = snapshotConfig
			snapshotConfigDarkTheme.identifier = "DarkTheme"
			verify(view: view, snapshotConfig: snapshotConfigDarkTheme,
				   file: file,
				   testName: testName,
				   line: line)

		} else {
			XCTFail("View doesn't support Themable protocol")
		}
	}
	
	@available(iOS 11.0, *)
	func verifySafeAreas(
		viewController: UIViewController,
		tolerance: Float = 0,
		file: StaticString = #file,
		testName: String = #function,
		line: UInt = #line
		) {
		viewController.additionalSafeAreaInsets = UIEdgeInsets(top: 44, left: 0, bottom: 34, right: 0)
		viewController.viewSafeAreaInsetsDidChange()
		viewController.view.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
		verify(view: viewController.view,
			   file: file,
			   testName: testName,
			   line: line)

	}
	
	// MARK: - verify the snapshots in multiple devices
	
	func verifyMultipleSize(view: UIView,
							inSizes sizes: [String:CGSize],
							snapshotConfig: SnapshotConfig = SnapshotConfig(),
							file: StaticString = #file,
							testName: String = #function,
							line: UInt = #line
		) {
		for (deviceName, size) in sizes {
			view.frame = CGRect(origin: .zero, size: size)
			
			var snapshotConfigClone = snapshotConfig
			snapshotConfigClone.deviceName = deviceName
			
			verify(view: view,
				   snapshotConfig: snapshotConfigClone,
				   file: file,
				   testName: testName,
				   line: line)

		}
	}

	func verifyMultipleConfig(viewController: UIViewController,
							inSizes sizes: [String:SnapshotTesting.ViewImageConfig],
							snapshotConfig: SnapshotConfig = SnapshotConfig(),
							file: StaticString = #file,
							testName: String = #function,
							line: UInt = #line
		) {
		for (deviceName, viewConfig) in sizes { ///TODO: use build-in method?
//			view.frame = CGRect(origin: .zero, size: size)
			
			var snapshotConfigClone = snapshotConfig
			snapshotConfigClone.deviceName = deviceName
//			snapshotConfigClone.viewConfig = viewConfig
			
			assertSnapshot(matching: viewController,
						   as: .image(on: viewConfig),
						   file: file,
						   testName:customTestName(testName: testName, snapshotConfig: snapshotConfigClone),
						   line: line)

//			verify(view: view,
//				   snapshotConfig: snapshotConfigClone,
//				   file: file,
//				   testName: testName,
//				   line: line)
			
		}
	}

	func verifyInAllIPhoneSizes(view: UIView,
								snapshotConfig: SnapshotConfig = SnapshotConfig(),
								file: StaticString = #file,
								testName: String = #function,
								line: UInt = #line) {
		verifyMultipleSize(view: view,
						   inSizes: XCTestCase.phoneScreenSizes,
						   snapshotConfig: snapshotConfig,
						   file: file,
						   testName: testName,
						   line: line)
		
	}

	
	func verifyInAllIPhoneSizes(viewController: UIViewController,
								snapshotConfig: SnapshotConfig = SnapshotConfig(),
								file: StaticString = #file,
								testName: String = #function,
								line: UInt = #line) {
		
		let phoneScreenSizes: [String:SnapshotTesting.ViewImageConfig] = [
			"iPhone-4_0_Inch": .iPhoneSe(.portrait),
			"iPhone-4_7_Inch": .iPhone8(.portrait),
			"iPhone-5_5_Inch": .iPhone8Plus(.portrait),
			"iPhone-5_8_Inch": .iPhoneX(.portrait),
			"iPhone-6_5_Inch": .iPhoneXsMax(.portrait)
		]

		verifyMultipleConfig(viewController: viewController,
						   inSizes: phoneScreenSizes,
						   snapshotConfig: snapshotConfig,
			file: file,
			testName: testName,
			line: line)

	}
	
	func verifyInAllDeviceSizes(view: UIView,
								snapshotConfig: SnapshotConfig = SnapshotConfig(),
		file: StaticString = #file,
		testName: String = #function,
		line: UInt = #line) {
		
		verifyMultipleSize(view: view,
						   inSizes: XCTestCase.deviceScreenSizes,
						   snapshotConfig: snapshotConfig,
						   file: file,
						   testName: testName,
						   line: line)
	}
	
}

// MARK: - UIAlertController
extension ZMSnapshotTestCase {
	func presentViewController(_ controller: UIViewController, file: StaticString = #file, line: UInt = #line) {
		// Given
		let window = UIWindow(frame: CGRect(origin: .zero, size: XCTestCase.DeviceSizeIPhone6))
		
		let container = UIViewController()
		container.loadViewIfNeeded()
		
		window.rootViewController = container
		window.makeKeyAndVisible()
		
		controller.loadViewIfNeeded()
		controller.view.layoutIfNeeded()
		
		// When
		let presentationExpectation = expectation(description: "It should be presented")
		container.present(controller, animated: false) {
			presentationExpectation.fulfill()
		}
		
		// Then
		waitForExpectations(timeout: 2, handler: nil)
	}
	
	func dismissViewController(_ controller: UIViewController, file: StaticString = #file, line: UInt = #line) {
		let dismissalExpectation = expectation(description: "It should be dismissed")
		controller.dismiss(animated: false) {
			dismissalExpectation.fulfill()
		}
		
		waitForExpectations(timeout: 2, handler: nil)
	}
	
	func verifyAlertController(_ controller: UIAlertController,
							   file: StaticString = #file,
							   testName: String = #function,
							   line: UInt = #line) {
		presentViewController(controller, file: file, line: line)
		verify(view: controller.view, file: file, testName: testName, line: line)
	}
}