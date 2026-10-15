Audio Studio (desktop)

Requisitos do sistema
  Linux:   sudo apt install ffmpeg libmpv-dev mpv zenity
  Windows: ffmpeg no PATH (winget install Gyan.FFmpeg)
  macOS:   brew install ffmpeg

Rodar
  flutter create --org com.example --platforms linux,windows,macos audio_studio
  Substituir pubspec.yaml e a pasta lib/ pelos deste projeto
  flutter pub get
  Se aparecer erro em png_decoder.dart (decodeLazy), rode: flutter pub upgrade archive image
  flutter run -d linux

yt-dlp (recomendado): pipx install yt-dlp (a versão do apt costuma estar desatualizada)
  Também é preciso deno ou nodejs instalado. O yt-dlp é tentado primeiro e o youtube_explode fica como alternativa.
  O botão de chave inglesa na aba Buscar verifica todas as dependências e testa um download real.

Jamendo (opcional): client_id gratuito em devportal.jamendo.com, colocado em lib/config.dart

Atalhos do editor
  Espaço reproduzir/pausar     S dividir no cursor
  Delete excluir               Shift+Delete excluir e fechar o espaço
  Ctrl+D duplicar              Ctrl+Z desfazer     Ctrl+Shift+Z refazer
  Home / End início / fim      Setas mover o cursor (Shift = 5 s)
  + / - zoom                   Ctrl+roda do mouse zoom no cursor
  Botão direito em um trecho: menu de contexto
