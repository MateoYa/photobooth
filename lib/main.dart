import 'dart:ffi';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as imgAdjustiment;
import 'dart:ui' as ui;
import 'dart:ui';
import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:flutter/services.dart';
import "package:image_cropper/image_cropper.dart";
import 'package:lindi_sticker_widget/draggable_widget.dart';
import 'package:lindi_sticker_widget/lindi_controller.dart';
import 'package:lindi_sticker_widget/lindi_sticker_widget.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// import 'package:share_plus/share_plus.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _cameras = await availableCameras();
  runApp(const CameraApp());
}



/// CameraApp is the Main Application.
class CameraApp extends StatefulWidget {
  /// Default Constructor
  const CameraApp({Key? key}) : super(key: key);

  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  late CameraController controller;
  List<Widget> widgets = [
    SizedBox(
        height: 100,
        width: 100,
        child: Image.asset("images/file.png")
    ),
        SizedBox(
        height: 100,
        width: 100,
        child: Image.asset("images/file1.png")
    ),
        SizedBox(
        height: 100,
        width: 100,
        child: Image.asset("images/file2.png")
    ),
        // const Align(alignment: Alignment.bottomCenter, child: Text("WCHS 2024 GRAD", selectionColor: Colors.white)),
        SizedBox(
        height: 100,
        width: 100,
        child: Image.asset("images/file3.png")
    ),
        SizedBox(
        height: 100,
        width: 100,
        child: Image.asset("images/file4.png")
    ),
        SizedBox(
        height: 100,
        width: 100,
        child: Image.asset("images/file5.png")
    ),
    const Icon(Icons.favorite, color: Colors.red, size: 50),
  ];
  final ScrollController _controllerOne = ScrollController();
  late bool isFinished;
  bool isPicturing = false;
  late Uint8List imgBytes;
  late var photoFiles = [];
  late File _croppedFile;
  File? photoFile;
  late var display;
  late var gloabalscale;
  LindiController lindiController = LindiController(borderColor: Colors.white, iconColor: Colors.black);
  List<DraggableWidget> dragAbleWidgets=List.empty();
  late var stickerSelector = false;
  var stickerID = 0;
  Timer? countdownTimer;
  Duration myDuration = const Duration(seconds: 5);
  bool CamaraFlashOff = true;
  @override
  void initState() {
    super.initState();
    isFinished = false;
    controller = CameraController(_cameras[1], ResolutionPreset.max,);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            // Handle access errors here.
            break;
          default:
            // Handle other errors here.
            break;
        }
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void takePhoto(int total, int count, ui.Size size) async {
    isPicturing = true;
    myDuration = const Duration(seconds: 5);
    try {
      if(count < total){
        isFinished = false;
        Future.delayed(Duration(seconds: 5), () async{
        setState(() {
          CamaraFlashOff = false;
        });
        XFile photo = await controller.takePicture();
        setState(() {
          CamaraFlashOff = true;
        });
        setState(() {
          photoFiles.add(photo.path);
        });
        takePhoto(total, count+1, size);
        }); 
      }else{
        stopTimer();
        GetPhotoFile(size);
      }
    }catch (e) {
      print(e);
    }
        

  }
  void startTimer() {
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => setCountDown());
  }

  void setCountDown() {
    const reduceSecondsBy = 1;
    setState(() {
      final seconds = myDuration.inSeconds - reduceSecondsBy;
      if (seconds < 0) {
        myDuration = Duration(seconds: 0);
      } else {
        myDuration = Duration(seconds: seconds);
      }
    });
  }
  void stopTimer(){
    countdownTimer!.cancel();
  }

  void deletePhoto() {
    isFinished = false;
    isPicturing = false;
    lindiController.widgets.clear();
    dragAbleWidgets = [];
    setState(() {
      photoFile = null;
    });
  }

  void sharePhoto() async{
    final tempDir = await getTemporaryDirectory();
    Uint8List? data = await lindiController.saveAsUint8List();
    
    File file = await File('${tempDir.path}/image.png').create();
    file.writeAsBytes(data!);
    XFile sharing = XFile('${tempDir.path}/image.png');
    await Share.shareXFiles([sharing], text: 'Image Shared');
    // deletePhoto();
  }

  void GetPhotoFile(ui.Size size) async{
    try{
      print("image taken 1");
      final recorder = ui.PictureRecorder();

      print("image taken 2");


      // var movingImage = await loadImage(File(photoFiles[photoFiles.length-1]).readAsBytesSync());

      // imageAdj = imgAdjustiment.copyResize(imageAdj!, width: 300, height: 300);
      
      var canvas = Canvas(recorder);
      final center = Offset(size.width/2, size.height/2);
      final radius = math.min(size.width, size.height) / 8;
      var scale = size.aspectRatio * controller.value.aspectRatio;

      // scale = 1 / scale;
      print(photoFiles.length);
      var maxSideSize = size.height/3-10;
      print(size.width);
      Paint background = Paint()
                      ..style = PaintingStyle.fill
                      ..color = Colors.black;
      canvas.drawRect(Rect.fromCenter(center: Offset(maxSideSize/2, size.height/2), width: maxSideSize.toDouble()+10, height: (maxSideSize.toDouble()+10)*3), background);
      for(int i = 0; i< photoFiles.length;i++){
        print(i);
        var movingImage = await loadImage(File(photoFiles[i]).readAsBytesSync());
        paintImage(canvas: canvas, rect: Rect.fromCenter(center: Offset(maxSideSize/2, maxSideSize/2 + (maxSideSize*i)+(10)), width: maxSideSize.toDouble()-10, height: maxSideSize.toDouble()-10), scale: scale, image: movingImage, fit: BoxFit.fitHeight, flipHorizontally: true);
      }
      photoFiles.clear();
      // // The circle should be paint before or it will be hidden by the path
      // Paint paintCircle = Paint()..color = Colors.black;
      // Paint paintBorder = Paint()
      //   ..color = Colors.white
      //   ..strokeWidth = size.width / 36
      //   ..style = PaintingStyle.stroke;
      // canvas.drawRect(Rect.fromCenter(center: center, width: 150, height: 150), paintCircle);
      // canvas.drawCircle(center, radius, paintBorder);

      // double drawImageWidth = 0;
      // var drawImageHeight = -size.height * 0.8;

      // Path path = Path()
      //   ..addRect(Rect.fromLTWH(0, 0,
      //       movingImage.width.toDouble(), movingImage.height.toDouble()));

      // canvas.clipPath(path);

      // canvas.drawImage(movingImage, Offset(0, 0), Paint());
      print("image taken 3");
      // canvas.drawImage(movingImage, Offset(0,0), Paint());
      print("image taken 4");
      final picture = recorder.endRecording();
      print("image taken 5");
      display = await picture.toImage(maxSideSize.toInt(), size.height.toInt());
      print("image taken 6");
      

      final pngBytes = await display.toByteData(format: ImageByteFormat.png);

      setState(() {
        gloabalscale = scale;
        imgBytes = Uint8List.view(pngBytes.buffer);
        lindiController = LindiController(borderColor: Colors.white, iconColor: Colors.black);
        lindiController.addWidget(widgets[0]);
      });
      isFinished = true;
    } catch(e){
      print(e);
    }
  }
  // Future<CroppedFile> _cropImage(String path) async {
  //   final Completer<CroppedFile> completer = new Completer();
  //   CroppedFile? croppedFile = await ImageCropper().cropImage(
  //     sourcePath: path,
  //     aspectRatioPresets: [
  //       CropAspectRatioPreset.square,
  //       CropAspectRatioPreset.ratio3x2,
  //     ],
  //     maxHeight: 1920,
  //     maxWidth: 1080,
  //   );
  //   return croppedFile!;
  // }
  Future<ui.Image> _cropImage(File flieImage) async{
    final Completer<ui.Image> completer = new Completer();
    var list = await flieImage.readAsBytes();
    var croppedImageData;
    print(list.length);
    ui.decodeImageFromList(list, (ui.Image localImage) {
      return completer.complete(localImage);
    });
    return completer.future;
  }

  Future<ui.Image> loadImage(Uint8List fileImage) async {
    final Completer<ui.Image> completer = new Completer();
    ui.decodeImageFromList(fileImage, (ui.Image localImage) {
      return completer.complete(localImage);
    });
    return completer.future;
  }

  void addSticker(int index) async{
    setState(() {
      stickerSelector = false;
    });
    
    lindiController.addWidget(
      Container(
        padding: const EdgeInsets.all(5),
        decoration: const BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.all(Radius.circular(20))
        ),
        child: const Icon(Icons.favorite, color: Colors.red, size: 50),
        // const Text(
        //   'This is a Text',
        //   style: TextStyle(color: Colors.white),
        // ),
      ));

  }
  void widgetSelctor() async{
    // dragAbleWidgets = lindiController.widgets;
    // lindiController.addWidget(lindiController.widgets[0]);
    Uint8List? data = await lindiController.saveAsUint8List();
    
    setState(() {
      stickerSelector=true; 
      imgBytes = data!;
    });

  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container();
    }
    String strDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = strDigits(myDuration.inMinutes.remainder(60));
    final seconds = myDuration.inSeconds.remainder(60);
    return MaterialApp(
        home: Scaffold(
      
      
      body:
      
      
      stickerSelector? Scrollbar(
                  controller: _controllerOne,
                  thumbVisibility: false,
                  child: GridView.builder(
                    controller: _controllerOne,
                    itemCount: widgets.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
                    itemBuilder: (BuildContext context, int index) {
                      return OutlinedButton(
                        child: widgets[index],
                        onPressed: (){setState(() {
                          stickerID = index;
                          stickerSelector=false;
                          setState(() {
                            lindiController = LindiController(borderColor: Colors.white, iconColor: Colors.black);
                            // for (DraggableWidget widget in dragAbleWidgets){
                            //   lindiController.addWidget(widget);
                            // }
                          });
                        });}                     
                      );                    
                    },
                  ),
                ):!isFinished//photoFile == null
          ?Row( 
          mainAxisAlignment: MainAxisAlignment.center,
          children: [SizedBox(
        height: 200,
        width: 200,
        child: Image.asset("images/file6.png")
    ),
            
            
            Stack(
        children: CamaraFlashOff?[
              Center(
              child: ClipRRect(
        child:  SizedOverflowBox(
        size: ui.Size(MediaQuery.sizeOf(context).width.toDouble()<= MediaQuery.sizeOf(context).height.toDouble()?MediaQuery.sizeOf(context).width.toDouble():MediaQuery.sizeOf(context).height.toDouble(), MediaQuery.sizeOf(context).width.toDouble()<= MediaQuery.sizeOf(context).height.toDouble()?MediaQuery.sizeOf(context).width.toDouble():MediaQuery.sizeOf(context).height.toDouble()), // aspect is 1:1
        alignment: Alignment.center,
        child: CameraPreview(controller),
      ),
      
      )),Center(
        child: ClipRRect(
        child:  SizedOverflowBox(
        size: ui.Size(MediaQuery.sizeOf(context).width.toDouble()<= MediaQuery.sizeOf(context).height.toDouble()?MediaQuery.sizeOf(context).width.toDouble():MediaQuery.sizeOf(context).height.toDouble(), MediaQuery.sizeOf(context).width.toDouble()<= MediaQuery.sizeOf(context).height.toDouble()?MediaQuery.sizeOf(context).width.toDouble():MediaQuery.sizeOf(context).height.toDouble()), // aspect is 1:1
        alignment: Alignment.center,
        child: Stack(
         children: [Align(
              alignment: Alignment.topCenter,
              child:SizedBox(
                width: 75,
                height: 75,
                child: Center(child:ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: const Color.fromARGB(255, 255, 255, 255),
                ),
                onPressed: (){},
                child: Text(
                '$seconds',
                style: const TextStyle(
                    color: Color.fromARGB(255, 0, 0, 0),
                    fontWeight: FontWeight.bold,
                    fontSize: 50,),
                    textAlign: TextAlign.center,
              )))))
              
              
              ]),
              
            )))]:[Center(
              child: ClipRRect(
        child:  SizedOverflowBox(
        size: ui.Size(MediaQuery.sizeOf(context).width.toDouble()<= MediaQuery.sizeOf(context).height.toDouble()?MediaQuery.sizeOf(context).width.toDouble():MediaQuery.sizeOf(context).height.toDouble(), MediaQuery.sizeOf(context).width.toDouble()<= MediaQuery.sizeOf(context).height.toDouble()?MediaQuery.sizeOf(context).width.toDouble():MediaQuery.sizeOf(context).height.toDouble()), // aspect is 1:1
        alignment: Alignment.center,
        child: Container())))],
      
      ),SizedBox(
        height: 200,
        width: 200,
        child: Image.asset("images/file.png")
    ),])
          // : Transform.scale(
          //   scale: gloabalscale,
          //   child: Center(
          //         child: Image.memory(Uint8List.view(imgBytes.buffer)),
          //       ),
          //   ),
            :Center(
              child: Transform.scale(
              origin: Offset(0, 200),
              scale: 0.9,
              child:  LindiStickerWidget(
                
                controller: lindiController,
                child: SizedBox(
                    width: MediaQuery.sizeOf(context).height/3,
                    height: MediaQuery.sizeOf(context).height,
                     child: Image.memory(Uint8List.view(imgBytes.buffer)),
                ),),
              )),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        
        children: !isFinished
            ? <Widget>[
              Center(
                child: FloatingActionButton(
                  onPressed: (){if (!isPicturing) {takePhoto(3, 0, MediaQuery.sizeOf(context));startTimer();}},
                  child: const Icon(Icons.camera_alt),
                ))
              ]
            : <Widget>[
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FloatingActionButton(
                      onPressed: deletePhoto,
                      child: const Icon(Icons.delete),
                    ),
                    const SizedBox(width: 16),
                    FloatingActionButton(
                      onPressed: sharePhoto,
                      child: const Icon(Icons.share),
                    ),
                    FloatingActionButton(
                     onPressed: (){setState(() {widgetSelctor();});},
                  tooltip: 'Add',
                  child: const Icon(Icons.add),
                ),
                FloatingActionButton(
                     onPressed: () async{
                    lindiController.addWidget(
                      Container(
                        padding: const EdgeInsets.all(5),
                        child: widgets[stickerID],
                        // const Text(
                        //   'This is a Text',
                        //   style: TextStyle(color: Colors.white),
                        // ),
                      ),
                    );

                  },
                  tooltip: 'add',
                  child: const Icon(Icons.select_all),
                ),
                  ],
                )
              ],
      ),
    ));
  }
}
