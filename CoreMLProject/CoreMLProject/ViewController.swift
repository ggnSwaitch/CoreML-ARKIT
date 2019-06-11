//
//  ViewController.swift
//  CoreMLProject
//
//  Created by Gagandeep Kaur Swaitch on 30/5/19.
//  Copyright © 2019 Gagandeep Kaur Swaitch. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision
import CoreML

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, SCNSceneRendererDelegate{
    
    @IBOutlet var sceneView: ARSCNView!
    
    var currentBuffer: CVPixelBuffer?

    lazy var recognizer = MLRecognizer(
        model: Inceptionv3().model,
        sceneView: sceneView
    )
    let detectionImages = ARReferenceImage.referenceImages(
        inGroupNamed: "AR Resources",
        bundle: nil
    )
    
//    lazy var sceneView: ARSCNView = {
//        let sceneView = ARSCNView()
//        sceneView.delegate = self
//        return sceneView
//    }()
    
    lazy var refreshButton = UIBarButtonItem(
        barButtonSystemItem: .refresh,
        target: self, action: #selector(refreshButtonPressed)
    )
    
    private lazy var predictionRequest: VNCoreMLRequest = {
        // Load the ML model through its generated class and create a Vision request for it.
        do {
            let model = try VNCoreMLModel(for: Inceptionv3().model)
            let request = VNCoreMLRequest(model: model)
            
            // This setting determines if images are scaled or cropped to fit our 224x224 input size. Here we try scaleFill so we don't cut part of the image.
            request.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFill
            return request
        } catch {
            fatalError("can't load Vision ML model: \(error)")
        }
    }()
    
    let visionQueue = DispatchQueue(label: "com.viseo.ARML.visionqueue")
    

    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.delegate = self;
        title = "ARKit + CoreML"
        navigationItem.rightBarButtonItem = refreshButton
        
//        view.addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        view.subviews.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        resetTracking()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.planeDetection = .horizontal
        sceneView.delegate = self
        sceneView.session.delegate = self as? ARSessionDelegate
        
        // Run the view's session
        sceneView.session.run(configuration)
//        print(#function, sceneView.session.currentFrame!)
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }

    // MARK: - ARSCNViewDelegate
    

    // Override to create and configure nodes for anchors added to the view's session.
//    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
//        let node = SCNNode()
//
//        guard let imageAnchor = anchor as? ARImageAnchor else { return nil }
//
//        // send off anchor to be snapshotted, cropped, deskewed, and classified
//        recognizer.classify(imageAnchor: imageAnchor) { [weak self] result in
//            if case .success(let classification) = result {
//
//                // update app with classification
//                self?.attachLabel(classification, to: node)
//            }
//        }
//        return node
//    }

    
    func session(_ session: ARSession,  didUpdate frame: ARFrame) {
        
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
            return
        }
        currentBuffer = frame.capturedImage
        
        startDetection()
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        startDetection()
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    private func startDetection() {
        // Here we will do our CoreML request on currentBuffer
        // Release currentBuffer to allow processing next frame
        guard let buffer = currentBuffer else { return }
        
        // Right orientation because the pixel data for image captured by an iOS device is encoded in the camera sensor's native landscape orientation
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
        
        // We perform our CoreML Requests asynchronously.
        visionQueue.async {
            // Run our CoreML Request
            try? requestHandler.perform([self.predictionRequest])
           
            guard (self.predictionRequest.results?.first as? VNClassificationObservation) != nil
     
                else {
                fatalError("Unexpected result type from VNCoreMLRequest")
            }
            let node = SCNNode()
            node.position = SCNVector3Make(25, 20, 20)
            // Rotate because SceneKit is rotated
            node.eulerAngles.x = -.pi / 2
            let classification = self.predictionRequest.results?.first.debugDescription
            self.attachLabel(classification as! String, to: node)
            // The resulting image (mask) is available as observation.pixelBuffer
            // Release currentBuffer when finished to allow processing next frame
            self.currentBuffer = nil
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor else { return }
        
        // send off anchor to be snapshotted, cropped, deskewed, and classified
        recognizer.classify(imageAnchor: imageAnchor) { [weak self] result in
            if case .success(let classification) = result {
                
                // update app with classification
                self?.attachLabel(classification, to: node)
            }
        }
    }
    
    
    func addIndicatorPlane(to imageAnchor: ARImageAnchor) {
        let node = sceneView.node(for: imageAnchor)
        let size = imageAnchor.referenceImage.physicalSize
        let geometry = SCNPlane(width: size.width, height: size.height)
        let plane = SCNNode(geometry: geometry)
        plane.geometry?.firstMaterial?.diffuse.contents = UIColor.darkGray
        plane.geometry?.firstMaterial?.fillMode = .lines
        plane.eulerAngles.x = -.pi / 2
        node?.addChildNode(plane)
    }
    
    // Adds a label below `node`
    func attachLabel(_ title: String, to node: SCNNode) {
//        let geometry = SCNText(string: title, extrusionDepth: 0)
//        geometry.flatness = 0.1
//        geometry.firstMaterial?.diffuse.contents = UIColor.darkText
//        let text = SCNNode(geometry: geometry)
//        text.scale = .init(0.00075, 0.00075, 0.00075)
//        text.eulerAngles.x = -.pi / 2
//        let box = text.boundingBox
//        text.pivot.m41 = (box.max.x - box.min.x) / 2.0
//        text.position.z = node.boundingBox.max.z + 0.012 // 1 cm below card
//        node.addChildNode(text)
        
        let alert = UIAlertController(title: "Something Detected", message: title, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
            switch action.style{
            case .default:
                print("default")
                
            case .cancel:
                print("cancel")
                
            case .destructive:
                print("destructive")
                
                
            }}))
        self.present(alert, animated: true, completion: nil)
    }
    
    @objc func refreshButtonPressed() {
        resetTracking()
    }
    
    func resetTracking() {
        let config = ARWorldTrackingConfiguration()
        config.detectionImages = detectionImages
        config.maximumNumberOfTrackedImages = 1
        config.isLightEstimationEnabled = true
        config.isAutoFocusEnabled = true
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
    
}

