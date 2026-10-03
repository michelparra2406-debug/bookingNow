// Sirve build/web_preview (entrada main_preview.dart) en http://localhost:8788
process.env.PORT = process.env.PORT || "8788";
process.env.WEB_DIR = "web_preview";
require("./serve_web.js");
