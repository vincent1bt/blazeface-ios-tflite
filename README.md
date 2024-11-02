# Face Detection in iOS using the BlazeFace Architecture and TensorFlow Lite

In this repository you can find the code for the iOS app that we created in [this post](https://vincentblog.link/posts/blaze-face-in-i-os-using-tensor-flow-lite).

We use the BlazeFace architecture to build the model since this architecture is suitable for low-end hardware and mobile devices.

You can read more about the original model [here](https://vincentblog.link/posts/face-detection-for-low-end-hardware-using-the-blaze-face-architecture).

The model is already in the repository due to its small size. You can also find a version of this app that uses CoreML to run the model[here](https://github.com/vincent1bt/blazeface-ios-coreml).

This app supports multiple face detection and low-end devices like iphone and ipad devices with the A9 CPU.

The app uses SwiftUI to build the interface so there are a lot of code that could improve.

## Install TensorFlowLite pod

```
pod install
```

and

```
open FaceRecognitionAppTF.xcworkspace
```
