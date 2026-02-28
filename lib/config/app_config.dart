// Configuration — update the URLs below after deploying to Railway
class AppConfig {
  // ──── CLOUD (Railway) ────
  // After deploying, Railway gives you a URL like: your-app.up.railway.app
  // Replace 'YOUR_APP.up.railway.app' with your actual Railway domain.
  static const String wsUrl = 'wss://YOUR_APP.up.railway.app/ws/query';
  static const String httpUrl = 'https://YOUR_APP.up.railway.app';

  // ──── LOCAL DEV (uncomment these and comment out the cloud URLs above) ────
  // static const String wsUrl = 'ws://192.168.1.7:8000/ws/query';
  // static const String httpUrl = 'http://192.168.1.7:8000';
}
