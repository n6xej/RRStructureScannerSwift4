//
//  MeshViewController.swift
//  RRStructureScanner
//
//  Created by Christopher Worley on 11/24/17.
//  Copyright © 2017 Ruthless Research, LLC. All rights reserved.
//

import MessageUI
import ImageIO

protocol MeshViewDelegate: class {
    
    func meshViewWillDismiss()
    func meshViewDidDismiss()
    func meshViewDidRequestColorizing(_ mesh: STMesh,  previewCompletionHandler: @escaping () -> Void, enhancedCompletionHandler: @escaping () -> Void) -> Bool
}

open class MeshViewController: UIViewController, UIGestureRecognizerDelegate, MFMailComposeViewControllerDelegate {

	@IBOutlet weak var eview: EAGLView!
	@IBOutlet weak var displayControl: UISegmentedControl!
	@IBOutlet weak var meshViewerMessageLabel: UILabel!
	
	weak var delegate : MeshViewDelegate?
	
	var context: EAGLContext? = nil
	var projectionMatrix: GLKMatrix4 = GLKMatrix4Identity
	var volumeCenter = GLKVector3Make(0,0,0)
	var displayLink: CADisplayLink?
	var renderer: MeshRenderer!
	var viewpointController: ViewpointController!
	var viewport = [GLfloat](repeating: 0, count: 4)
	var modelViewMatrixBeforeUserInteractions: GLKMatrix4?
	var projectionMatrixBeforeUserInteractions: GLKMatrix4?
	
	var mailViewController: MFMailComposeViewController?
	
	// force the view to redraw.
    var needsDisplay: Bool = false
	
    var _mesh: STMesh? = nil
	
    var mesh: STMesh?
	{
        get {
            return _mesh
        }
        set {
            _mesh = newValue

            if _mesh != nil {

                self.renderer!.uploadMesh(_mesh!)
                self.trySwitchToColorRenderingMode()
                self.needsDisplay = true
            }
        }
    }

    required public init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)

    }

    override open func viewDidLoad() {
		
        super.viewDidLoad()
		
		renderer = MeshRenderer.init()
		
		viewpointController = ViewpointController.init(screenSizeX: Float(self.eview.frame.size.width), screenSizeY: Float(self.eview.frame.size.height))
		
		setupGL(context!)
		
		mesh = _mesh

		setCameraProjectionMatrix(projectionMatrix)
		resetMeshCenter(volumeCenter)

        let font = UIFont.boldSystemFont(ofSize: 14)
        let attributes: [AnyHashable: Any] = [NSAttributedStringKey.font : font]
        
        displayControl.setTitleTextAttributes(attributes, for: UIControlState())
		
		renderer.setRenderingMode(.lightedGray)
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
		
        if displayLink != nil {
            displayLink!.invalidate()
            displayLink = nil
        }
        
        displayLink = CADisplayLink(target: self, selector: #selector(MeshViewController.draw))
        displayLink!.add(to: RunLoop.main, forMode: RunLoopMode.commonModes)
		
        viewpointController.reset()
    }
	
	// Make sure the status bar is disabled (iOS 7+)
	override open var prefersStatusBarHidden : Bool {
		return true
	}

    override open func didReceiveMemoryWarning () {
        
    }
    
    func setupGL (_ context: EAGLContext) {

        (self.eview as EAGLView).context = context

        EAGLContext.setCurrent(context)

        renderer.initializeGL( GLenum(GL_TEXTURE3))

        self.eview.setFramebuffer()
        
        let framebufferSize: CGSize = self.eview.getFramebufferSize()
		
		viewport[0] = 0
		viewport[1] = 0
		viewport[2] = Float(framebufferSize.width)
		viewport[3] = Float(framebufferSize.height)
    }
    
	@IBAction func dismissView(_ sender: AnyObject) {
		
		displayControl.selectedSegmentIndex = 1
		renderer.setRenderingMode(.lightedGray)
		
        if delegate?.meshViewWillDismiss != nil {
            delegate?.meshViewWillDismiss()
        }
		
        renderer.releaseGLBuffers()
        renderer.releaseGLTextures()
		
        displayLink!.invalidate()
        displayLink = nil
		
        mesh = nil

        self.eview.context = nil

		dismiss(animated: true, completion: {
			if self.delegate?.meshViewDidDismiss != nil {
				self.delegate?.meshViewDidDismiss()
			}
		})
    }
	
	//MARK: - MeshViewer setup when loading the mesh
    
    func setCameraProjectionMatrix (_ projection: GLKMatrix4) {

        viewpointController.setCameraProjection(projection)
        projectionMatrixBeforeUserInteractions = projection
    }
    
    func resetMeshCenter (_ center: GLKVector3) {

        viewpointController.reset()
        viewpointController.setMeshCenter(center)
        modelViewMatrixBeforeUserInteractions = viewpointController.currentGLModelViewMatrix()
    }
	
	func saveJpegFromRGBABuffer( _ filename: String, src_buffer: UnsafeMutableRawPointer, width: Int, height: Int)
	{
		let file: UnsafeMutablePointer<FILE>? = fopen(filename, "w")
		if file == nil {
			return
		}
        
		var colorSpace: CGColorSpace?
		var alphaInfo: CGImageAlphaInfo!
		var bmcontext: CGContext?
		colorSpace = CGColorSpaceCreateDeviceRGB()
		alphaInfo = .noneSkipLast

		bmcontext = CGContext(data: src_buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace!, bitmapInfo: alphaInfo.rawValue)!
		var rgbImage: CGImage? = bmcontext!.makeImage()

		bmcontext = nil
		colorSpace = nil
		
		var jpgData: CFMutableData? = CFDataCreateMutable(nil, 0)
		var imageDest: CGImageDestination? = CGImageDestinationCreateWithData(jpgData!, "public.jpeg" as CFString, 1, nil)

		var kcb = kCFTypeDictionaryKeyCallBacks
		var vcb = kCFTypeDictionaryValueCallBacks
		
        // Our empty IOSurface properties dictionary
		var options: CFDictionary? = CFDictionaryCreate(kCFAllocatorDefault, nil, nil, 0, &kcb, &vcb)
		
		CGImageDestinationAddImage(imageDest!, rgbImage!, options!)
		CGImageDestinationFinalize(imageDest!)
		
		imageDest = nil
		rgbImage = nil
		options = nil

		fwrite(CFDataGetBytePtr(jpgData!), 1, CFDataGetLength(jpgData!), file!)
		fclose(file!)
		
		jpgData = nil
	}

	// create preview image from current viewpoint
	
	func prepareScreenShotCurrentViewpoint (screenshotPath: String) {

		let framebufferSize: CGSize = self.eview.getFramebufferSize()
		let width: Int32 = Int32.init(framebufferSize.width)
		let height: Int32 = Int32.init(framebufferSize.height)

		var screenShotRgbaBuffer = [UInt32](repeating: 0, count: Int(width*height))
		
		var screenTopRowBuffer = [UInt32](repeating: 0, count: Int(width))
		
		var screenBottomRowBuffer = [UInt32](repeating: 0, count: Int(width))
		
		// tell glReadPixels to read from front buffer
		glReadBuffer(GLuint(GL_FRONT))
		glReadPixels(0, 0, width, height, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &screenShotRgbaBuffer)
		
		// flip the buffer
		for h in 0..<height/2 {
			
			glReadPixels(0, h, width, 1, UInt32(GL_RGBA), UInt32(GL_UNSIGNED_BYTE), &screenTopRowBuffer)
			
			glReadPixels(0, (height - h - 1), width, 1, UInt32(GL_RGBA), UInt32(GL_UNSIGNED_BYTE), &screenBottomRowBuffer)
			
			let topIdx = Int(width * h)
			let bottomIdx = Int(width * (height - h - 1))
			
			withUnsafeMutablePointer(to: &screenShotRgbaBuffer[topIdx]) { (one) -> () in
				withUnsafePointer(to: &screenBottomRowBuffer[0], { (two) -> () in
					
					one.withMemoryRebound(to: UInt32.self, capacity: Int(width), { (onePtr) -> () in
						two.withMemoryRebound(to: UInt32.self, capacity: Int(width), { (twoPtr) -> () in
							
							memcpy(onePtr, twoPtr, Int(width) * Int(MemoryLayout<UInt32>.size))
						})
					})
				})
			}
			
			withUnsafeMutablePointer(to: &screenShotRgbaBuffer[bottomIdx]) { (one) -> () in
				withUnsafePointer(to: &screenTopRowBuffer[0], { (two) -> () in
					
					one.withMemoryRebound(to: UInt32.self, capacity: Int(width), { (onePtr) -> () in
						two.withMemoryRebound(to: UInt32.self, capacity: Int(width), { (twoPtr) -> () in
							
							memcpy(onePtr, twoPtr, Int(width) * Int(MemoryLayout<UInt32>.size))
						})
					})
				})
			}
		}

		
		saveJpegFromRGBABuffer(screenshotPath, src_buffer: &screenShotRgbaBuffer, width: Int(width), height: Int(height))

	}
	
	@IBAction func emailMesh(sender: AnyObject) {
		
		mailViewController = MFMailComposeViewController.init()
		
		if mailViewController == nil {
			let alert = UIAlertController.init(title: "The email could not be sent.", message: "Please make sure an email account is properly setup on this device.", preferredStyle: .alert)
			
			let defaultAction = UIAlertAction.init(title: "OK", style: .default, handler: nil)
			
			alert.addAction(defaultAction)
			
			present(alert, animated: true, completion: nil)
			
			return
		}
		
		mailViewController!.mailComposeDelegate = self
		
		if UIDevice.current.userInterfaceIdiom == .pad {
			mailViewController!.modalPresentationStyle = .formSheet
		}
		
		// Setup paths and filenames.
		
		let zipFilename = "Model.zip"
		let screenshotFilename = "Preview.jpg"
		
		let fullPathFilename = FileMgr.sharedInstance.full(screenshotFilename)
		
		FileMgr.sharedInstance.del(screenshotFilename)
		
		// Take a screenshot and save it to disk.
		
		prepareScreenShotCurrentViewpoint(screenshotPath: fullPathFilename)
		
		// since file is save in prepareScreenShot() need to getData() here
		
		if let sshot = NSData(contentsOfFile: fullPathFilename) {
			
			mailViewController?.addAttachmentData(sshot as Data, mimeType: "image/jpeg", fileName: screenshotFilename)
		}
		else {
			let alert = UIAlertController.init(title: "Error", message: "no pic", preferredStyle: .alert)
			
			let defaultAction = UIAlertAction.init(title: "OK", style: .default, handler: nil)
			
			alert.addAction(defaultAction)
			
			present(alert, animated: true, completion: nil)
		}
		
		mailViewController!.setSubject("3D Model")
		
		let messageBody = "This model was captured with the open source https://github.com/n6xej/RRStructureScanner\n\nFor information about building an app that uses the Structure Sensor email Chris at cworley@ruthlessresearch.com";
		
		mailViewController?.setMessageBody(messageBody, isHTML: false)
		
		if let meshToSend = mesh {
			let zipfile = FileMgr.sharedInstance.saveMesh(zipFilename, data: meshToSend)
			
			if zipfile != nil {
				mailViewController?.addAttachmentData(zipfile!, mimeType: "application/zip", fileName: zipFilename)
			}
		}
		else {
			
			mailViewController = nil
			
			let alert = UIAlertController.init(title: "The email could not be sent", message: "Exporting the mesh failed", preferredStyle: .alert)
			
			let defaultAction = UIAlertAction.init(title: "OK", style: .default, handler: nil)
			
			alert.addAction(defaultAction)
			
			present(alert, animated: true, completion: nil)
			
			return
		}
		
		present(mailViewController!, animated: true, completion: nil)
	}
	
	//MARK: Mail Delegate
	
	public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
		mailViewController?.dismiss(animated: true, completion: nil)
	}
	
    //MARK: Rendering
	
	@objc func draw () {
        
        self.eview.setFramebuffer()
		
        glViewport(GLint(viewport[0]), GLint(viewport[1]), GLint(viewport[2]), GLint(viewport[3]))
		
        let viewpointChanged = viewpointController.update()
		
        // If nothing changed, do not waste time and resources rendering.
        if !needsDisplay && !viewpointChanged {
            return
        }
		
        var currentModelView = viewpointController.currentGLModelViewMatrix()
        var currentProjection = viewpointController.currentGLProjectionMatrix()
        
        renderer!.clear()
		
		withUnsafePointer(to: &currentProjection) { (one) -> () in
			withUnsafePointer(to: &currentModelView, { (two) -> () in
				
				one.withMemoryRebound(to: GLfloat.self, capacity: 16, { (onePtr) -> () in
					two.withMemoryRebound(to: GLfloat.self, capacity: 16, { (twoPtr) -> () in
						
						renderer!.render(onePtr,modelViewMatrix: twoPtr)
					})
				})
			})
		}
		
        needsDisplay = false
		
        let _ = self.eview.presentFramebuffer()

    }
	
    //MARK: Touch & Gesture Control

    @IBAction func tapGesture(_ sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            viewpointController.onTouchBegan()
        }
    }
	
	@IBAction func pinchScaleGesture(_ sender: UIPinchGestureRecognizer) {

        // Forward to the ViewpointController.
        if sender.state == .began {
            viewpointController.onPinchGestureBegan(Float(sender.scale))
        }
        else if sender.state == .changed {
            viewpointController.onPinchGestureChanged(Float(sender.scale))
        }
    }
    
	@IBAction func oneFingerPanGesture(_ sender: UIPanGestureRecognizer) {

        let touchPos = sender.location(in: view)
        let touchVel = sender.velocity(in: view)
        let touchPosVec = GLKVector2Make(Float(touchPos.x), Float(touchPos.y))
        let touchVelVec = GLKVector2Make(Float(touchVel.x), Float(touchVel.y))
		
        if sender.state == .began {
            viewpointController.onOneFingerPanBegan(touchPosVec)
        }
        else if sender.state == .changed {
            viewpointController.onOneFingerPanChanged(touchPosVec)
        }
        else if sender.state == .ended {
            viewpointController.onOneFingerPanEnded(touchVelVec)
        }
    }
	
	@IBAction func twoFingersPanGesture(_ sender: AnyObject) {

        if sender.numberOfTouches != 2 {
            return
        }
		
		let touchPos = sender.location(in: view)
		let touchVel = sender.velocity(in: view)
		let touchPosVec = GLKVector2Make(Float(touchPos.x), Float(touchPos.y))
		let touchVelVec = GLKVector2Make(Float(touchVel.x), Float(touchVel.y))
		
        if sender.state == .began {
            viewpointController.onTwoFingersPanBegan(touchPosVec)
        }
        else if sender.state == .changed {
            viewpointController.onTwoFingersPanChanged(touchPosVec)
        }
        else if sender.state == .ended {
            viewpointController.onTwoFingersPanEnded(touchVelVec)
        }
    }

    //MARK: UI Control
    
    func trySwitchToColorRenderingMode() {
   
        // Choose the best available color render mode, falling back to LightedGray
        // This method may be called when colorize operations complete, and will
        // switch the render mode to color, as long as the user has not changed
        // the selector.
		
        if displayControl.selectedSegmentIndex == 2 {
			
			if	mesh!.hasPerVertexUVTextureCoords() {
              
				renderer.setRenderingMode(.textured)
			}
			else if mesh!.hasPerVertexColors() {
             
				renderer.setRenderingMode(.perVertexColor)
			}
			else {
            
				renderer.setRenderingMode(.lightedGray)
			}
		}
		else if displayControl.selectedSegmentIndex == 3 {
			
			if	mesh!.hasPerVertexUVTextureCoords() {
				
				renderer.setRenderingMode(.textured)
			}
			else if mesh!.hasPerVertexColors() {
				
				renderer.setRenderingMode(.perVertexColor)
			}
			else {
				
				renderer.setRenderingMode(.lightedGray)
			}
		}
    }
	
    @IBAction func displayControlChanged(_ sender: AnyObject) {

        switch displayControl.selectedSegmentIndex {
		case 0: // x-ray
          
            renderer.setRenderingMode(.xRay)
			
		case 1: // lighted-gray
         
            renderer.setRenderingMode(.lightedGray)
			
        case 2: // color
            
            trySwitchToColorRenderingMode()
			
            let meshIsColorized: Bool = mesh!.hasPerVertexColors() || mesh!.hasPerVertexUVTextureCoords()
			
            if !meshIsColorized {
              
                colorizeMesh()
			}

			default:
				break
		}
		
		needsDisplay = true
	}
    
    func colorizeMesh() {
        
        let _ = delegate?.meshViewDidRequestColorizing(self.mesh!, previewCompletionHandler: {
            }, enhancedCompletionHandler: {
                
                // Hide progress bar.
                self.hideMeshViewerMessage()
        })
    }
	
    func hideMeshViewerMessage() {
		
        UIView.animate(withDuration: 0.5, animations: {
            self.meshViewerMessageLabel.alpha = 0.0
            }, completion: { _ in
                self.meshViewerMessageLabel.isHidden = true
        })
    }
    
    func showMeshViewerMessage(_ msg: String) {
        
        meshViewerMessageLabel.text = msg
        
        if meshViewerMessageLabel.isHidden == true {
            
            meshViewerMessageLabel.alpha = 0.0
            meshViewerMessageLabel.isHidden = false
            
            UIView.animate(withDuration: 0.5, animations: {
                self.meshViewerMessageLabel.alpha = 1.0
            })
        }
    }
}

