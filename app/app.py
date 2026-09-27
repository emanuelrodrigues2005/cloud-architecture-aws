from flask import Flask, render_template, request, redirect, url_for
import psycopg2
import redis
import os

app = Flask(__name__)

# PostgreSQL
DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "mural")
DB_USER = os.getenv("DB_USER", "mural_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "12345678")

# Redis
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = os.getenv("REDIS_PORT", "6379")
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "12345678")

redis_client = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    password=REDIS_PASSWORD,
    decode_responses=True
)


def get_db():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )


def init_db():
    conn = get_db()
    cursor = conn.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            message TEXT NOT NULL
        )
    """)

    conn.commit()
    cursor.close()
    conn.close()


@app.route("/")
def index():
    conn = get_db()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, name, message
        FROM messages
        ORDER BY id DESC
    """)

    messages = cursor.fetchall()

    cursor.close()
    conn.close()

    try:
      redis_client.set("last_access", "ok")
      redis_status = "Online"
    except Exception as e:
      print("ERRO REDIS:", repr(e), )
      redis_status = "Offline"

    return render_template(
        "index.html",
        messages=messages,
        redis_status=redis_status
    )


@app.route("/messages", methods=["POST"])
def add_message():
    name = request.form.get("name")
    message = request.form.get("message")

    if not name or not message:
        return redirect(url_for("index"))

    conn = get_db()
    cursor = conn.cursor()

    cursor.execute(
        """
        INSERT INTO messages (name, message)
        VALUES (%s, %s)
        """,
        (name, message)
    )

    conn.commit()

    cursor.close()
    conn.close()

    # Apenas para demonstrar comunicação com Redis
    try:
        redis_client.incr("messages_created")
    except Exception:
        pass

    return redirect(url_for("index"))


@app.route("/messages/clear", methods=["POST"])
def clear_messages():
    conn = get_db()
    cursor = conn.cursor()

    cursor.execute("TRUNCATE TABLE messages RESTART IDENTITY")

    conn.commit()

    cursor.close()
    conn.close()

    return redirect(url_for("index"))

@app.route("/health")
def health():
    db_status = "offline"
    redis_status = "offline"

    try:
        conn = get_db()
        conn.close()
        db_status = "online"
    except Exception:
        pass

    try:
        redis_client.ping()
        redis_status = "online"
    except Exception:
        pass

    return {
        "application": "online",
        "postgresql": db_status,
        "redis": redis_status
    }


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=8080)

