import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;

import 'email_outbox.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  // Send any emails left queued from last time (runs in the background).
  unawaited(EmailOutbox.instance.start());
  // Ask for "add to Photos" permission at launch, so the one-time prompt is
  // answered during setup rather than popping up in front of a guest.
  unawaited(Gal.requestAccess().catchError((Object _) => false));
  runApp(const CameraApp());
}

// Photo strip layout, in output pixels.
const int kPhotoCount = 3;
const int kFirstCountdownSeconds = 5;
const int kNextCountdownSeconds = 3;
const Color kMainBackground = Color(0xFF030A1C);
const double kStripWidth = 600;
const double kStripPadding = 24; // sides, and above the logo band
const double kStripTopPadding = 48; // above the first photo
const double kPhotoGap = kStripTopPadding; // between photos, same as top
const double kStripBorder = 3; // thin faded white border around the strip
const double kPhotoSize = kStripWidth - 2 * kStripPadding;
const double kLogoBandHeight = 150;
const double kStripHeight = kStripTopPadding +
    kPhotoCount * kPhotoSize +
    (kPhotoCount - 1) * kPhotoGap +
    kStripPadding +
    kLogoBandHeight;
const Color kGold = Color(0xFFE8B23A);
const String kFont = 'Times New Roman';
const List<Color> kIgniteGradient = [
  Color(0xFFFFE08A),
  Color(0xFFE8B23A),
  Color(0xFFF26B1D),
];

/// CameraApp is the Main Application.
class CameraApp extends StatefulWidget {
  const CameraApp({Key? key}) : super(key: key);

  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  late CameraController controller;
  // Solid white flash, on/off with no fade, independent of how long the
  // camera takes to save the photo.
  static const flashDuration = Duration(milliseconds: 250);
  bool isFlashOn = false;
  Timer? flashTimer;
  bool isPicturing = false;
  bool isCapturing = false;
  int secondsLeft = kFirstCountdownSeconds;
  int shotNumber = 0;
  Uint8List? stripBytes;
  Timer? countdownTimer;
  final List<String> photoFiles = [];

  // Email flow on the result screen.
  ResultStage stage = ResultStage.review;
  final emailController = TextEditingController();
  String? emailError;
  Timer? doneTimer;
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  void initState() {
    super.initState();
    controller = CameraController(
        _cameras.length > 1 && !Platform.isMacOS ? _cameras[1] : _cameras.first,
        ResolutionPreset.max,
        enableAudio: false);
    controller.initialize().then((_) async {
      // Turn off the camera's own flash; on iPad the front camera fakes one
      // with a warm orange screen glow. The app draws its own white flash.
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (mounted) setState(() {});
    }).catchError((Object e) {
      debugPrint('Camera error: $e');
    });
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    flashTimer?.cancel();
    doneTimer?.cancel();
    emailController.dispose();
    controller.dispose();
    super.dispose();
  }

  void startSession() {
    if (isPicturing) return;
    photoFiles.clear();
    setState(() {
      isPicturing = true;
      shotNumber = 1;
      secondsLeft = kFirstCountdownSeconds;
    });
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> tick() async {
    if (secondsLeft > 1) {
      setState(() => secondsLeft--);
      return;
    }
    countdownTimer?.cancel();
    setState(() => isCapturing = true);
    try {
      final capture = controller.takePicture();
      setState(() => isFlashOn = true);
      flashTimer?.cancel();
      flashTimer = Timer(flashDuration, () {
        if (mounted) setState(() => isFlashOn = false);
      });
      photoFiles.add((await capture).path);
    } catch (e) {
      debugPrint('Capture failed: $e');
    }
    if (!mounted) return;
    setState(() => isCapturing = false);

    if (photoFiles.length < kPhotoCount) {
      setState(() {
        shotNumber = photoFiles.length + 1;
        secondsLeft = kNextCountdownSeconds;
      });
      countdownTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => tick());
    } else {
      final bytes = await buildStrip();
      if (!mounted) return;
      setState(() {
        stripBytes = bytes;
        isPicturing = false;
      });
    }
  }

  Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }

  /// Draws the photos stacked vertically on navy, with the ACE logo
  /// in a band at the bottom.
  Future<Uint8List?> buildStrip() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, kStripWidth, kStripHeight),
        Paint()..color = kMainBackground);

    for (int i = 0; i < photoFiles.length; i++) {
      final photo = await decode(await File(photoFiles[i]).readAsBytes());
      final top = kStripTopPadding + i * (kPhotoSize + kPhotoGap);
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(kStripPadding, top, kPhotoSize, kPhotoSize),
        image: photo,
        fit: BoxFit.cover,
        flipHorizontally: true,
        filterQuality: FilterQuality.high,
      );
    }

    // Bottom band: ACE logo on the left, event title on the right.
    final logoData = await rootBundle.load('images/ace_white.png');
    final logo = await decode(logoData.buffer.asUint8List());
    const bandTop = kStripHeight - kLogoBandHeight;
    // Centre of the band, nudged up since the last photo's gap sits above it.
    const bandCenterY = bandTop + (kLogoBandHeight - kStripPadding / 2) / 2;
    const logoHeight = kLogoBandHeight * 0.7;
    final logoWidth = logoHeight * logo.width / logo.height;
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(
          kStripPadding, bandCenterY - logoHeight / 2, logoWidth, logoHeight),
      image: logo,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    // "IGNITE 2026" on one line, vertically centred with the logo, with IGNITE in
    // a gold-to-orange gradient. Shrinks to fit the space beside the logo.
    final maxTitleWidth = kStripWidth - 3 * kStripPadding - logoWidth;
    TextPainter layoutTitle(double fontSize, {Shader? igniteShader}) {
      final base = TextStyle(
        fontFamily: kFont,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
        height: 1,
      );
      return TextPainter(
        textDirection: TextDirection.ltr,
        maxLines: 1,
        text: TextSpan(style: base, children: [
          TextSpan(
            text: 'IGNITE ',
            style: igniteShader == null
                ? const TextStyle(color: Colors.white)
                : TextStyle(foreground: Paint()..shader = igniteShader),
          ),
          const TextSpan(text: '2026', style: TextStyle(color: Colors.white)),
        ]),
      )..layout();
    }

    var fontSize = 58.0;
    var probe = layoutTitle(fontSize);
    if (probe.width > maxTitleWidth) {
      fontSize *= maxTitleWidth / probe.width;
      probe = layoutTitle(fontSize);
    }
    // Gradient spans just the word IGNITE, in the title's own coordinates.
    final igniteWidth = probe
        .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 6))
        .fold<double>(0, (w, b) => b.right > w ? b.right : w);
    final title = layoutTitle(fontSize,
        igniteShader: const LinearGradient(colors: kIgniteGradient)
            .createShader(Rect.fromLTWH(0, 0, igniteWidth, probe.height)));
    canvas.save();
    canvas.translate(kStripWidth - kStripPadding - title.width,
        bandCenterY - title.height / 2);
    title.paint(canvas, Offset.zero);
    canvas.restore();

    // Thin white border around the outside edge of the whole strip.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, kStripWidth, kStripHeight)
          .deflate(kStripBorder / 2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3) // soft, faded edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = kStripBorder,
    );

    final image = await recorder
        .endRecording()
        .toImage(kStripWidth.toInt(), kStripHeight.toInt());
    // JPEG instead of PNG: 5-10x smaller, so emails upload much faster.
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;
    return compute(
        _encodeJpeg, (rgba.buffer.asUint8List(), image.width, image.height));
  }

  /// Back to the camera for the next guest.
  void retake() {
    doneTimer?.cancel();
    emailController.clear();
    setState(() {
      stripBytes = null;
      shotNumber = 0;
      stage = ResultStage.review;
      emailError = null;
    });
  }

  void openEmailForm() {
    setState(() {
      stage = ResultStage.email;
      emailError = null;
    });
  }

  /// Quietly keeps a copy of the strip in the iPad's Photos app.
  Future<void> saveToPhotos(Uint8List bytes) async {
    try {
      if (!await Gal.hasAccess()) return; // never prompt in front of a guest
      await Gal.putImageBytes(bytes,
          name: 'IGNITE-2026-${DateTime.now().millisecondsSinceEpoch}');
    } catch (e) {
      debugPrint('Save to Photos failed: $e');
    }
  }

  Future<void> submitEmail() async {
    final bytes = stripBytes;
    final email = emailController.text.trim();
    if (bytes == null) return;
    if (!_emailPattern.hasMatch(email)) {
      setState(() => emailError = 'Please enter a valid email address');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      emailError = null;
      stage = ResultStage.sending;
    });
    unawaited(saveToPhotos(bytes));
    // Saving to the outbox takes a moment; the actual sending carries on in
    // the background (and retries if offline), so the guest doesn't wait.
    try {
      await EmailOutbox.instance.enqueue(email, bytes);
    } catch (e) {
      debugPrint('Email queue error: $e');
      if (!mounted) return;
      setState(() {
        stage = ResultStage.email;
        emailError = 'Something went wrong, please try again';
      });
      return;
    }
    if (!mounted) return;
    setState(() => stage = ResultStage.done);
    doneTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) retake();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: kGold, brightness: Brightness.dark),
        scaffoldBackgroundColor: kMainBackground,
      ),
      home: Scaffold(
        body: !controller.value.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : stripBytes == null
                ? buildCameraScreen()
                : buildResultScreen(),
      ),
    );
  }

  Widget buildCameraScreen() {
    return Stack(
      children: [
        const ColoredBox(color: kMainBackground, child: SizedBox.expand()),
        SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            const headerSpace = 170.0; // minimum room kept above the camera
            const buttonSpace = 112.0; // Start button row below the camera
            final side = [
              constraints.maxWidth - 32,
              constraints.maxHeight - headerSpace - buttonSpace,
            ].reduce((a, b) => a < b ? a : b).clamp(100.0, 2000.0);
            return Column(
              children: [
                // Title sits centred between the top of the screen and the
                // top of the camera view.
                Expanded(child: Center(child: buildHeader())),
                buildPreview(side),
                SizedBox(
                  height: buttonSpace,
                  child: Center(
                    // Keeps its space while hidden so the camera doesn't jump.
                    child: Visibility(
                      visible: !isPicturing,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: buildStartButton(),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
        // Full-screen flash, drawn over everything.
        if (isFlashOn)
          const IgnorePointer(
              child: ColoredBox(color: Colors.white, child: SizedBox.expand())),
      ],
    );
  }

  Widget buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // Shrinks to fit on narrow screens instead of wrapping.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('images/ace_white.png', height: 110),
            const SizedBox(width: 24),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                    fontFamily: kFont,
                    fontSize: 60,
                    fontWeight: FontWeight.w500,
                    height: 1.1),
                children: [
                  TextSpan(
                      text: 'IGNITE ',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: kGold)),
                  TextSpan(
                      text: 'Case Competition 2026',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPreview(double side) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: side, child: CameraPreview(controller)),
            ),
            if (isPicturing && !isCapturing)
              Center(child: buildCountdown(side)),
          ],
        ),
      ),
    );
  }

  Widget buildStartButton() {
    return FilledButton.icon(
      onPressed: startSession,
      icon: const Icon(Icons.camera_alt, size: 28),
      label: const Text('Start'),
      style: FilledButton.styleFrom(
        backgroundColor: kGold,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget buildCountdown(double side) {
    final size = side * 0.3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.45),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.85), width: 4),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child)),
            child: Text(
              '$secondsLeft',
              key: ValueKey('$shotNumber-$secondsLeft'),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.55,
                fontWeight: FontWeight.w300,
                height: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Photo $shotNumber of $kPhotoCount',
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget buildResultScreen() {
    switch (stage) {
      case ResultStage.review:
        return buildReviewScreen();
      case ResultStage.email:
        return buildEmailScreen();
      case ResultStage.sending:
        return buildStatusScreen(
          icon: const SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(strokeWidth: 6, color: kGold)),
          title: 'Sending…',
          message: emailController.text.trim(),
        );
      case ResultStage.done:
        return buildStatusScreen(
          icon: const Icon(Icons.mark_email_read_outlined,
              size: 96, color: kGold),
          title: 'On its way!',
          message: 'Your photo strip is being emailed to\n'
              '${emailController.text.trim()}\n\n'
              'Check your inbox (and spam folder) in a minute.',
          action: FilledButton(
            onPressed: retake,
            style: primaryButtonStyle,
            child: const Text('Done'),
          ),
        );
    }
  }

  static final primaryButtonStyle = FilledButton.styleFrom(
    backgroundColor: kGold,
    foregroundColor: Colors.black,
    minimumSize: const Size(260, 80),
    textStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
  );

  static final secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: const BorderSide(color: Colors.white70, width: 2),
    minimumSize: const Size(260, 80),
    textStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
  );

  Widget buildStripPreview() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: const [BoxShadow(color: Colors.white10, blurRadius: 24)],
      ),
      child: Image.memory(stripBytes!, fit: BoxFit.contain),
    );
  }

  Widget buildEmailScreen() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(flex: 2, child: Center(child: buildStripPreview())),
            const SizedBox(width: 40),
            Expanded(
              flex: 3,
              // Scrolls so the field stays reachable above the keyboard.
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    const Text('Get your photo strip',
                        style: TextStyle(
                            fontSize: 40, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text("Enter your email and we'll send it to you.",
                        style: TextStyle(fontSize: 22, color: Colors.white70)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: emailController,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => submitEmail(),
                      onChanged: (_) {
                        if (emailError != null) {
                          setState(() => emailError = null);
                        }
                      },
                      style: const TextStyle(fontSize: 26),
                      decoration: InputDecoration(
                        hintText: 'you@example.com',
                        errorText: emailError,
                        errorStyle: const TextStyle(fontSize: 18),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        prefixIcon: const Icon(Icons.email_outlined, size: 30),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 24),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: kGold, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 20,
                      runSpacing: 16,
                      children: [
                        FilledButton.icon(
                          onPressed: submitEmail,
                          icon: const Icon(Icons.send, size: 30),
                          label: const Text('Send'),
                          style: primaryButtonStyle,
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() => stage = ResultStage.review);
                          },
                          icon: const Icon(Icons.arrow_back, size: 30),
                          label: const Text('Back'),
                          style: secondaryButtonStyle,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildStatusScreen({
    required Widget icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 28),
              Text(title,
                  style: const TextStyle(
                      fontSize: 48, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, color: Colors.white70)),
              if (action != null) ...[const SizedBox(height: 40), action],
            ],
          ),
        ),
      ),
    );
  }

  Widget buildReviewScreen() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: buildStripPreview()),
            const SizedBox(width: 32),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: openEmailForm,
                  icon: const Icon(Icons.email_outlined, size: 34),
                  label: const Text('Email me'),
                  style: primaryButtonStyle,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: retake,
                  icon: const Icon(Icons.refresh, size: 34),
                  label: const Text('Retake'),
                  style: secondaryButtonStyle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum ResultStage { review, email, sending, done }

/// Encodes raw RGBA pixels as a JPEG. Runs on a background isolate via
/// compute() so the UI doesn't freeze while encoding.
Uint8List _encodeJpeg((Uint8List, int, int) args) {
  final (pixels, width, height) = args;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: pixels.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: 90);
}
