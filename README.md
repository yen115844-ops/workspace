NODE_ENV=development
PORT=8686
# PostgreSQL
DB_HOST=localhost
DB_PORT=5432
DB_USERNAME=postgres
DB_PASSWORD=123456
DB_DATABASE=hancitywork
# Redis: optional for MVP (only when need cache/presence/queue)
# REDIS_HOST=localhost
# REDIS_PORT=6379
# REDIS_PASSWORD=
JWT_SECRET=
JWT_EXPIRES_IN=15m
REFRESH_SECRET=
REFRESH_EXPIRES_IN=7d
CORS_ORIGIN=http://localhost:3001

# Upload MVP: Multer, save to disk (no S3 needed)
UPLOAD_DIR=./uploads

# Optional: OAuth2 (phase 2)
# GOOGLE_CLIENT_ID=
# GOOGLE_CLIENT_SECRET=
# MICROSOFT_CLIENT_ID=
# MICROSOFT_CLIENT_SECRET=

# Optional: S3 when scaling (replace Multer)
# S3_ENDPOINT=http://localhost:9000
# S3_BUCKET=hancitywork
# S3_ACCESS_KEY=
# S3_SECRET_KEY=
# S3_REGION=

# Optional: Vector search
# OPENAI_API_KEY=
# EMBEDDING_API_URL=

# Optional: LiveKit
# LIVEKIT_URL=
# LIVEKIT_API_KEY=
# LIVEKIT_API_SECRET=

# Mail (gửi email mời workspace)
# Để gửi email thật: dùng Gmail SMTP, Mailtrap, SendGrid, etc.
# MAIL_HOST=smtp.gmail.com
# MAIL_PORT=587
# MAIL_USER=your-email@gmail.com
# MAIL_PASS=your-app-password
# MAIL_FROM="HanCity Work" <noreply@hancitywork.com>
APP_URL=http://localhost:3001

FIREBASE_PROJECT_ID="workspace-af384"
FIREBASE_CLIENT_EMAIL="firebase-adminsdk-fbsvc@workspace-af384.iam.gserviceaccount.com"
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDuGLxiLaxwmpUw\nNQ9pI/q1aMHCKssTtWfVdfs+LE2yEPIOS1SJwbLOvJE2+JvThJHNN1C6Llk8YTl7\n7q6xWplErqVMq59GlJy15HhIcUcCCPiXcPjtU9WXIBC0SOWIesj2GVpFo8IQnpzy\n6fk6iX0vGbvJc+siZRmi+goh2IHR9JzEehMUAWp6ZPVY84kmN7y+1U+1D2zI1uti\nuTQPpDFlSBSBjFv+b6e8cbx6T8sTyhRdL2L1JG8wzsNaLs0VzABCHfZh2xaK8xX2\n0+ulgr7NexxX/rkVNLuaS5TlXe+M9PxGwY26szRp0KuoMeVGM5n6OfuUUE3bN2Kp\nAdr/oum/AgMBAAECggEAHlsJ/YxsLUkQFz7UkaeUKbfK6DnzfTZGIDl0CEe2uiqd\n6cOh6hRHe0MgUn1cxJlky2CviqUpHGEa5pmWLSdrXg3UJlPFMUb2OdyAl1/V2UUS\niKBPJFbpZuSgLJQUq5NX9sRhtXo83kiSowfAjj2EN9KUlgkQ4+g23gf57bnAR2ek\n9mT56FujdhI9IWLj53TcbOFoxSQX35uYe7qD3OLvT5Vj6aEOIZl5n9T7UZdSqeuW\nJWbqgzKt7NI0qTODrv/2nA3DGq/hnqt6c5j0h8SHO1wAwGer9tXHawYoB03jvy+q\nKQ9J/6lozm+eJJ3CeeIa+dYWED01IT3L6C/cdfCucQKBgQD4+55Dwn3DWW90hSV5\nvtXEo7pHsSpQl42ZXefuUnOylXucgey7++2uyapqRRblQdwv5exn6WqemGtDMO8T\nQt/DHh7AhIrx9l8tfQLRq/8X9onU6l502VBzZyBEidBmz2RF5DOpljYo4X04e/cL\n1tLFqHZbNeQuqXobx2EnEVJxLwKBgQD0zpMYbU1OQV5PtcNjmmcqf7JlbjMN1QzW\nUj2zA6YcSwVFy/fPW1spdHvDEAXUs3OctfoMXk5YtPCTfzMq6QI39lGfhd8IDesl\nxA6HGihlG7AnSpAIOm3PfX70lMnAp0dKvrtTh8KQlb96lILQ/WKcWDobzSgrb5nK\n/r3ODmtMcQKBgHH0X6QtoPfGuC9BPTyybg5YzUpAuNg39PPrudom3JMwvWmNQXds\nP4WPATMwOeFlukwl1IRenZDGu9j9zX4oTld0Mqj0QM+rbjZYj/C84rzp9n1/Ywnh\n6GNZILidxsc3RnKClm6YtGMTiQdQHWrKwJ78kmb+jFga8ytBnqKN2Ai7AoGAQ7Yr\ni3MYEdAU1PlSbOdVJ7UgU9vSNT47icA/npcgx+ycLb0H8wuywFmercptwnJMRQk0\ne11OUEzjyfhB39mJKo9v7i6qDOFErDJ5TjcW+zhYVdXS1uPKYby1c9L/ptDd8Den\nOqhvUWyKBM61DDc5okLo962cMb9xi2tAdpEYbpECgYByf+L3zXgTBZHPs88TwFlL\nC1XVcqyr9kh6DswAuOl07WYRaun1P6dP5p2DSEG/bkYNM3cZgs+dmGWN6skJdDHA\nm+9ZTXgoqe/m8NwXYjN5wGHPDR8jd2u0jnMxgdW4frJ/M49NoDQtQcjrK1qy7s3U\nvLHCqapQavBkevzLpNw1Vw==\n-----END PRIVATE KEY-----\n"
tiendev@ptb68:~/workspace/backend$ 
