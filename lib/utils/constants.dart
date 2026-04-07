class AppConstants {
  static const int signalingPort = 9090;

  static String signalingUrl(String host) => 'ws://$host:$signalingPort';
}
