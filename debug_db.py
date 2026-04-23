
from app import app, db, User
from sqlalchemy import inspect

with app.app_context():
    inspector = inspect(db.engine)
    tables = inspector.get_table_names()
    print(f"Tables found: {tables}")
    
    users = User.query.all()
    print(f"Number of users: {len(users)}")
    for u in users:
        print(f"User: {u.username}, Trust Score: {u.trust_score}")
