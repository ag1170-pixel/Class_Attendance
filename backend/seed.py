"""Seed a demo institution: one teacher, one room+camera, one section, students.

Usage:  python -m backend.seed            # creates backend/attendance.db
Returns the created ids (handy for tests / manual API calls).
"""
from __future__ import annotations

from .db import Database, new_id


def seed(db: Database) -> dict:
    db.init_schema()
    inst = new_id()
    db.execute("INSERT INTO institution(id,name,timezone) VALUES (?,?,?)",
               (inst, "Demo University", "Asia/Kolkata"))

    bld = new_id()
    db.execute("INSERT INTO building(id,institution_id,name) VALUES (?,?,?)",
               (bld, inst, "Main Block"))
    room = new_id()
    db.execute("INSERT INTO room(id,building_id,code,capacity) VALUES (?,?,?,?)",
               (room, bld, "A-101", 60))
    cam = new_id()
    db.execute(
        "INSERT INTO camera(id,room_id,vms_camera_ref,stream_uri,"
        "resolution_w,resolution_h,faces_students) VALUES (?,?,?,?,?,?,1)",
        (cam, room, "CAM-A101", "webcam:0", 1920, 1080),
    )

    teacher = new_id()
    db.execute(
        "INSERT INTO app_user(id,institution_id,email,full_name,role)"
        " VALUES (?,?,?,?, 'teacher')",
        (teacher, inst, "prof@demo.edu", "Prof. Rao"),
    )

    course = new_id()
    db.execute("INSERT INTO course(id,institution_id,code,title) VALUES (?,?,?,?)",
               (course, inst, "CS301", "Operating Systems"))
    section = new_id()
    db.execute(
        "INSERT INTO section(id,course_id,term,teacher_id,room_id)"
        " VALUES (?,?,?,?,?)",
        (section, course, "2026-ODD", teacher, room),
    )
    db.execute(
        "INSERT INTO schedule(id,section_id,day_of_week,start_time,end_time)"
        " VALUES (?,?,?,?,?)",
        (new_id(), section, 0, "09:00", "10:00"),
    )

    students = []
    for i, name in enumerate(["Aarav Sharma", "Diya Patel", "Kabir Singh",
                              "Ananya Rao", "Vivaan Gupta"], start=1):
        sid = new_id()
        db.execute(
            "INSERT INTO student(id,institution_id,register_no,roll_no,full_name,"
            "program,batch_year) VALUES (?,?,?,?,?,?,?)",
            (sid, inst, f"REG{i:03d}", str(i), name, "B.Tech CSE", 2024),
        )
        db.execute(
            "INSERT INTO section_roster(section_id,student_id) VALUES (?,?)",
            (section, sid),
        )
        students.append({"id": sid, "name": name, "register_no": f"REG{i:03d}"})

    return {
        "institution": inst, "room": room, "camera": cam,
        "teacher": teacher, "course": course, "section": section,
        "students": students,
    }


if __name__ == "__main__":
    import json
    from .db import DEFAULT_DB
    DEFAULT_DB.unlink(missing_ok=True)
    db = Database()
    ids = seed(db)
    print(json.dumps(ids, indent=2))
    print(f"\nSeeded {DEFAULT_DB}")
