import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/app_log.dart';
import 'services/dependency_manager.dart';
import 'state/project_controller.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    AppLog.error('flutter', details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.error('async', error, stack);
    return true;
  };

  AppLog.info('app', 'iniciado');

  JustAudioMediaKit.ensureInitialized();

  runApp(const AudioStudioApp());
}

class AudioStudioApp extends StatelessWidget {
  const AudioStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProjectController()..init(),
      child: MaterialApp(
        title: 'Audio Studio',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const DependencyBootstrap(
          child: HomeScreen(),
        ),
      ),
    );
  }
}

class DependencyBootstrap extends StatefulWidget {
  const DependencyBootstrap({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<DependencyBootstrap> createState() => _DependencyBootstrapState();
}

class _DependencyBootstrapState extends State<DependencyBootstrap> {
  String _message = 'Verificando dependências...';
  double _progress = 0;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _message = 'Verificando dependências...';
        _progress = 0;
      });
    }

    try {
      await DependencyManager.instance.initialize(
        onProgress: (message, progress) {
          if (!mounted) return;

          setState(() {
            _message = message;
            _progress = progress.clamp(0.0, 1.0);
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _message = 'Dependências prontas';
        _progress = 1;
      });
    } catch (e, stack) {
      AppLog.error('bootstrap', e, stack);

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = '$e';
        _message = 'Não foi possível preparar as dependências.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _error == null) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  "assets/icons/audio_studio.png",
                  width: 64,
                  height: 64,
                ),
                const SizedBox(height: 24),
                Text(
                  'Audio Studio',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                if (_loading) ...[
                  LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A primeira inicialização pode levar alguns minutos.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _error!,
                        style: TextStyle(
                          color: colors.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _initialize,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
