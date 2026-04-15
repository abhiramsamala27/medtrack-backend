from flask import Flask, render_template, request, jsonify, session, redirect, url_for, flash
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime, timedelta
import os
import logging
import json
from flask_cors import CORS
import firebase_admin
from firebase_admin import credentials, messaging
from dotenv import load_dotenv

# Load .env file if it exists
load_dotenv()

# --- Setup Logging ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)
# Enable CORS for all origins (useful for the Flutter app)
CORS(app)

app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'medication-trust-debugged-secret')
# Use DATABASE_URL from Render, fallback to local SQLite
db_url = os.environ.get('DATABASE_URL', 'sqlite:///med_adherence_v2.db')
if db_url and db_url.startswith("postgres://"):
    db_url = db_url.replace("postgres://", "postgresql://", 1)
app.config['SQLALCHEMY_DATABASE_URI'] = db_url
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
login_manager = LoginManager()
login_manager.login_view = 'login'
login_manager.init_app(app)

# Get Firebase credentials from environment variable
cred_json = os.environ.get("FIREBASE_CREDENTIALS")

if cred_json:
    try:
        # Convert the JSON string to a Python dictionary
        cred_dict = json.loads(cred_json)

        # Initialize Firebase app
        cred = credentials.Certificate(cred_dict)
        firebase_admin.initialize_app(cred)
        logger.info("Firebase Admin initialized successfully.")
    except Exception as e:
        logger.error(f"Error initializing Firebase Admin: {e}")
else:
    logger.warning("FIREBASE_CREDENTIALS not found in environment. Notifications will be disabled.")

# --- Database Models ---

class User(UserMixin, db.Model):
    __tablename__ = 'users'
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password = db.Column(db.String(120), nullable=False)
    trust_score = db.Column(db.Float, default=70.0)
    streak = db.Column(db.Integer, default=0)
    last_taken_date = db.Column(db.Date, nullable=True)
    
    medications = db.relationship('Medication', backref='owner', lazy=True)
    logs = db.relationship('Adherence', backref='user', lazy=True)

    def __init__(self, **kwargs):
        super(User, self).__init__(**kwargs)

class Medication(db.Model):
    __tablename__ = 'medicines'
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    dosage = db.Column(db.String(80), nullable=False)
    duration_days = db.Column(db.Integer, default=7)
    start_date = db.Column(db.Date, default=lambda: datetime.now().date())
    status = db.Column(db.String(20), default='active') # 'active' or 'completed'
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    
    timings = db.relationship('MedicationTiming', backref='medication', lazy=True, cascade="all, delete-orphan")

    def __init__(self, **kwargs):
        super(Medication, self).__init__(**kwargs)

class MedicationTiming(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    med_id = db.Column(db.Integer, db.ForeignKey('medicines.id'), nullable=False)
    time_str = db.Column(db.String(10), nullable=False) # "09:00"

    def __init__(self, **kwargs):
        super(MedicationTiming, self).__init__(**kwargs)

class Adherence(db.Model):
    __tablename__ = 'adherence'
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    med_id = db.Column(db.Integer, db.ForeignKey('medicines.id'), nullable=False)
    scheduled_time = db.Column(db.DateTime, nullable=False) # Date + Time
    taken_time = db.Column(db.DateTime, nullable=True)
    status = db.Column(db.String(20), default='PENDING') # PENDING, TAKEN, MISSED
    trust_impact = db.Column(db.Float, default=0.0)

    # Help with joins
    medication = db.relationship('Medication', backref='events', lazy=True)

    def __init__(self, **kwargs):
        super(Adherence, self).__init__(**kwargs)

# --- Initialize Database ---
with app.app_context():
    try:
        db.create_all()
        logger.info("Database tables created successfully.")
        # Seed demo user
        if not User.query.filter_by(username='demo').first():
            demo = User(username='demo', password=generate_password_hash('password'))
            db.session.add(demo)
            db.session.commit()
            logger.info("Demo user 'demo' created.")
    except Exception as e:
        logger.error(f"Database initialization error: {e}")

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

# --- Auth Routes ---

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        try:
            data = request.get_json() or request.form
            username = data.get('username')
            password = data.get('password')
            
            user = User.query.filter_by(username=username).first()
            if user and check_password_hash(user.password, password):
                login_user(user)
                logger.info(f"User {username} logged in.")
                return jsonify({"status": "success", "redirect": url_for('dashboard')})
            return jsonify({"status": "error", "message": "Invalid credentials"}), 401
        except Exception as e:
            logger.error(f"Login error: {e}")
            return jsonify({"status": "error", "message": str(e)}), 500
    return render_template('login.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        try:
            data = request.get_json() or request.form
            username = data.get('username')
            password = data.get('password')
            
            if User.query.filter_by(username=username).first():
                return jsonify({"status": "error", "message": "User exists"}), 400
            
            new_user = User(username=username, password=generate_password_hash(password))
            db.session.add(new_user)
            db.session.commit()
            login_user(new_user)
            logger.info(f"New user {username} registered.")
            return jsonify({"status": "success"})
        except Exception as e:
            logger.error(f"Registration error: {e}")
            return jsonify({"status": "error", "message": str(e)}), 500
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    logger.info(f"User {current_user.username} logged out.")
    logout_user()
    return redirect(url_for('login'))

# --- Main Logic Routes ---

@app.route('/')
def index():
    return redirect(url_for('dashboard'))

@app.route('/status')
def status():
    """Diagnostic endpoint to check backend health and Firebase status"""
    return jsonify({
        "server": "online",
        "firebase_initialized": len(firebase_admin._apps) > 0,
        "database_type": "postgres" if "postgresql" in app.config['SQLALCHEMY_DATABASE_URI'] else "sqlite"
    })

@app.route('/ping')
def ping():
    """Lightweight endpoint for keep-alive services to prevent Render from sleeping."""
    return "pong", 200

@app.route('/dashboard')
@login_required
def dashboard():
    return render_template('dashboard.html')

@app.route('/medications')
@login_required
def medications_page():
    return render_template('medications.html')

@app.route('/history')
@login_required
def history_page():
    return render_template('history.html')

@app.route('/add_medicine', methods=['POST'])
@login_required
def add_medicine():
    try:
        data = request.get_json() or {}
        name = (data.get('name') or '').strip()
        dosage = (data.get('dosage') or '').strip()
        duration = int(data.get('duration', 7))
        timings = data.get('timings', []) or []

        cleaned_timings = [t.strip() for t in timings if isinstance(t, str) and t.strip()]

        if not name:
            return jsonify({"status": "error", "message": "Medicine name is required."}), 400

        if not dosage:
            return jsonify({"status": "error", "message": "Dosage is required."}), 400

        if not cleaned_timings:
            return jsonify({"status": "error", "message": "At least one valid timing is required."}), 400

        new_med = Medication(
            name=name,
            dosage=dosage,
            duration_days=duration,
            user_id=current_user.id
        )
        db.session.add(new_med)
        db.session.flush()

        for t in cleaned_timings:
            tm = MedicationTiming(med_id=new_med.id, time_str=t)
            db.session.add(tm)

        db.session.commit()
        logger.info(f"Medicine {name} added for user {current_user.username}")
        return jsonify({"status": "success"})
    except Exception as e:
        db.session.rollback()
        logger.error(f"Add medicine error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/medications/<int:med_id>', methods=['DELETE', 'PUT'])
@login_required
def update_delete_med(med_id):
    try:
        med = Medication.query.get_or_404(med_id)
        if med.user_id != current_user.id:
            return jsonify({"status": "unauthorized"}), 403
        
        if request.method == 'DELETE':
            db.session.delete(med)
            db.session.commit()
            logger.info(f"Medication {med_id} deleted.")
            return jsonify({"status": "success"})
            
        if request.method == 'PUT':
            data = request.get_json()
            med.name = data.get('name', med.name)
            med.dosage = data.get('dosage', med.dosage)
            med.duration_days = int(data.get('duration', med.duration_days))
            
            if 'timings' in data:
                MedicationTiming.query.filter_by(med_id=med.id).delete()
                Adherence.query.filter_by(med_id=med.id, status='PENDING').delete()
                for t in data['timings']:
                    tm = MedicationTiming(med_id=med.id, time_str=t)
                    db.session.add(tm)
            
            db.session.commit()
            logger.info(f"Medication {med_id} updated.")
            return jsonify({"status": "success"})
    except Exception as e:
        db.session.rollback()
        logger.error(f"Update/Delete error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/mark_taken', methods=['POST'])
@login_required
def mark_taken():
    try:
        data = request.get_json()
        event_id = data.get('event_id')
        taken_time_str = data.get('taken_time')

        event = Adherence.query.get_or_404(event_id)
        
        if event.user_id != current_user.id:
            return jsonify({"status": "error", "message": "Unauthorized"}), 403
            
        if event.status != 'PENDING':
            return jsonify({"status": "error", "message": "Already recorded"}), 400
            
        event.status = 'TAKEN'
        if taken_time_str:
            # Handle native ISO format appending fallback via timezone naive approach
            taken_time_str = taken_time_str.replace("Z", "+00:00")
            event.taken_time = datetime.fromisoformat(taken_time_str)
        else:
            event.taken_time = datetime.now()
            
        event.trust_impact = 2.0
        
        # Update Stats
        today = datetime.now().date()
        if current_user.last_taken_date == today - timedelta(days=1):
            current_user.streak += 1
        elif current_user.last_taken_date != today:
            current_user.streak = 1
        current_user.last_taken_date = today
        current_user.trust_score = min(100.0, current_user.trust_score + 2.0)
        
        # Check course completion
        med = Medication.query.get(event.med_id)
        total_doses = med.duration_days * len(med.timings)
        taken_doses = Adherence.query.filter_by(med_id=med.id, status='TAKEN').count()
        
        completed = False
        if taken_doses >= total_doses:
            med.status = 'completed'
            completed = True
            
        db.session.commit()
        logger.info(f"Dose marked TAKEN for {med.name} (Event ID: {event_id})")
        return jsonify({"status": "success", "message": "Dose recorded!", "completed": completed})
    except Exception as e:
        db.session.rollback()
        logger.error(f"Mark taken error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/mark_missed', methods=['POST'])
@login_required
def mark_missed():
    try:
        data = request.get_json()
        event_id = data.get('event_id')
        event = Adherence.query.get_or_404(event_id)
        
        if event.user_id != current_user.id:
            return jsonify({"status": "error", "message": "Unauthorized"}), 403
            
        if event.status != 'PENDING':
            return jsonify({"status": "error", "message": "Already recorded"}), 400
            
        event.status = 'MISSED'
        event.trust_impact = -1.0
        current_user.streak = 0
        current_user.trust_score = max(0.0, current_user.trust_score - 1.0)
        
        db.session.commit()
        return jsonify({"status": "success"})
    except Exception as e:
        db.session.rollback()
        logger.error(f"Mark missed error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

# --- API Endpoints ---

@app.route('/api/stats')
@login_required
def api_stats():
    # Performance calculation
    events = Adherence.query.filter(Adherence.user_id == current_user.id, Adherence.status != 'PENDING').all()
    taken = sum(1 for e in events if e.status == 'TAKEN')
    total = len(events)
    rate = round(taken/total*100) if total > 0 else 100
    
    return jsonify({
        "username": current_user.username,
        "trust_score": round(current_user.trust_score),
        "streak": current_user.streak,
        "adherence_pct": rate
    })

@app.route('/api/doses/today')
@login_required
def api_today_doses():
    local_time_str = request.args.get('local_time')
    if local_time_str:
        now_dt = datetime.strptime(local_time_str, "%Y-%m-%dT%H:%M")
        today = now_dt.date()
    else:
        now_dt = datetime.now()
        today = datetime.now().date()
        
    active_meds = Medication.query.filter_by(user_id=current_user.id, status='active').all()
    
    for med in active_meds:
        # Check overall duration expiry
        end_date = med.start_date + timedelta(days=med.duration_days)
        if today >= end_date:
            med.status = 'completed'
            continue
            
        # Create today's events if missing
        for t_obj in med.timings:
            time_obj = datetime.strptime(t_obj.time_str, "%H:%M").time()
            sched_dt = datetime.combine(today, time_obj)
            
            exists = Adherence.query.filter_by(med_id=med.id, scheduled_time=sched_dt).first()
            if not exists:
                new_e = Adherence(user_id=current_user.id, med_id=med.id, scheduled_time=sched_dt)
                db.session.add(new_e)
                db.session.flush()
                exists = new_e
                
            # Auto-mark Missed if > 1 hour late
            if exists.status == 'PENDING' and now_dt > (sched_dt + timedelta(hours=1)):
                # Do not penalize if it's the very first day of the medication!
                if med.start_date != today:
                    exists.status = 'MISSED'
                    exists.trust_impact = -1.0
                    current_user.streak = 0
    
    db.session.commit()
    
    events = Adherence.query.join(Medication).filter(
        Adherence.user_id == current_user.id,
        Medication.status == 'active',
        Adherence.scheduled_time >= datetime.combine(today, datetime.min.time()),
        Adherence.scheduled_time <= datetime.combine(today, datetime.max.time())
    ).order_by(Adherence.scheduled_time).all()
    
    return jsonify([{
        "id": e.id,
        "med_id": e.med_id,
        "med_name": e.medication.name,
        "dosage": e.medication.dosage,
        "scheduled_time": e.scheduled_time.strftime("%H:%M"),
        "status": e.status,
        "taken_time": e.taken_time.strftime("%H:%M") if e.taken_time else None
    } for e in events])

@app.route('/get_medicines')
@login_required
def get_medicines():
    """Endpoint for Flutter app to fetch medicine details for scheduling"""
    active_meds = Medication.query.filter_by(user_id=current_user.id, status='active').all()
    return jsonify([{
        "medicine_name": m.name,
        "dosage": m.dosage,
        "duration": m.duration_days,
        "timings": [t.time_str for t in m.timings]
    } for m in active_meds])

@app.route('/api/sync_schedule')
@login_required
def api_sync_schedule():
    """Endpoint for Flutter app to fetch all upcoming doses for native scheduling"""
    active_meds = Medication.query.filter_by(user_id=current_user.id, status='active').all()
    
    sync_data = []
    for med in active_meds:
        for t_obj in med.timings:
            sync_data.append({
                "med_id": med.id,
                "name": med.name,
                "dosage": med.dosage,
                "time": t_obj.time_str
            })
    return jsonify(sync_data)

@app.route('/api/medications', methods=['GET'])
@login_required
def api_meds():
    active = Medication.query.filter_by(user_id=current_user.id, status='active').all()
    return jsonify([{
        "id": m.id,
        "name": m.name,
        "dosage": m.dosage,
        "duration": m.duration_days,
        "timings": [t.time_str for t in m.timings]
    } for m in active])

@app.route('/api/medications/completed', methods=['GET'])
@login_required
def api_completed():
    done = Medication.query.filter_by(user_id=current_user.id, status='completed').all()
    return jsonify([{
        "id": m.id,
        "name": m.name,
        "dosage": m.dosage
    } for m in done])

@app.route('/api/history')
@login_required
def api_history():
    logs = Adherence.query.filter(
        Adherence.user_id == current_user.id,
        Adherence.status != 'PENDING'
    ).order_by(Adherence.scheduled_time.desc()).limit(50).all()
    
    return jsonify([{
        "med_name": Medication.query.get(l.med_id).name,
        "scheduled_time": l.scheduled_time.strftime("%b %d, %H:%M"),
        "taken_time": l.taken_time.strftime("%H:%M") if l.taken_time else "N/A",
        "status": l.status
    } for l in logs])

@app.route('/api/report/weekly')
@login_required
def api_weekly():
    today = datetime.now().date()
    days = []
    total_taken = 0
    total_missed = 0
    total_expected = 0
    
    active_ids = [m.id for m in current_user.medications]
    
    for i in range(6, -1, -1):
        date = today - timedelta(days=i)
        start_of_day = datetime.combine(date, datetime.min.time())
        end_of_day = datetime.combine(date, datetime.max.time())
        
        events = Adherence.query.filter(
            Adherence.user_id == current_user.id,
            Adherence.scheduled_time >= start_of_day,
            Adherence.scheduled_time <= end_of_day
        ).all()
        
        taken = sum(1 for e in events if e.status == 'TAKEN')
        missed = sum(1 for e in events if e.status == 'MISSED')
        total = len(events)
        
        total_taken += taken
        total_missed += missed
        total_expected += total
        
        rate = (taken / total * 100) if total > 0 else 100
        
        days.append({
            "name": date.strftime("%a"),
            "date": date.strftime("%b %d"),
            "adherence": round(rate),
            "events": [{"status": e.status, "med_name": Medication.query.get(e.med_id).name} for e in events]
        })
    
    overall = (total_taken / total_expected * 100) if total_expected > 0 else 100
    
    return jsonify({
        "days": days,
        "total_taken": total_taken,
        "total_missed": total_missed,
        "adherence_pct": round(overall)
    })

@app.route('/send-notification', methods=['POST'])
def send_notification():
    """Endpoint for sending push notifications via FCM"""
    try:
        data = request.get_json()
        device_token = data.get('deviceToken') or data.get('fcmToken')
        title = data.get('title', 'MedTrack Pro')
        body = data.get('body', 'Don\'t forget your medication!')

        if not device_token:
            return jsonify({"status": "error", "message": "deviceToken or fcmToken is required"}), 400

        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            token=device_token,
        )

        response = messaging.send(message)
        logger.info(f"Successfully sent FCM message: {response}")
        return jsonify({"status": "success", "message_id": response})
    except Exception as e:
        logger.warning(f"Error sending FCM message (Check credentials): {e}")
        return jsonify({"status": "error", "message": f"FCM Error: {str(e)}"}), 500

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(debug=False, host="0.0.0.0", port=port)