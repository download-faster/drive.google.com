# server.py — VM SSH Manager | Render + MongoDB Atlas | KHONG probe, KHONG token
import os, re, base64, ipaddress
from datetime import datetime, timezone
from typing import Optional, List

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, field_validator
from pymongo import MongoClient, ASCENDING
from pymongo.errors import PyMongoError

MONGODB_URI = os.environ.get("MONGODB_URI", "").strip()
DB_NAME = os.environ.get("MONGODB_DB", "vm_manager")
ADMIN_KEY = os.environ.get("ADMIN_KEY", "")

# Nhan ca comment o cuoi (user@host, nt authority\...) - dung chuan file .pub
KEY_RE = re.compile(
    r"^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)"
    r"|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)"
    r"\s+(?P<blob>[A-Za-z0-9+/=]+)"
    r"(?:\s+\S.*)?$"
)
NAME_RE = re.compile(r"^[^\s]{1,64}$")
USER_RE = re.compile(r"^[^\s]{1,64}$")

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

client = None
vms = None
keys_col = None
if MONGODB_URI:
    client = MongoClient(
        MONGODB_URI,
        serverSelectionTimeoutMS=5000,
        connectTimeoutMS=10000,
        socketTimeoutMS=20000,
        retryWrites=True, tz_aware=True,
    )
    vms = client[DB_NAME]["vms"]
    keys_col = client[DB_NAME]["authorized_keys"]

_idx_done = False
def ensure_indexes():
    global _idx_done
    if _idx_done or vms is None: return
    try:
        vms.create_index([("updated_at", ASCENDING)])
        _idx_done = True
    except PyMongoError: pass

def db_guard():
    if vms is None: raise HTTPException(503, "db_not_configured")
    ensure_indexes()

def now(): return datetime.now(timezone.utc)

def require_admin(req: Request):
    if not ADMIN_KEY or req.headers.get("x-admin-key") != ADMIN_KEY:
        raise HTTPException(403, "unauthorized")

def valid_ip(v: str) -> bool:
    try:
        ipaddress.ip_address(v.strip()); return True
    except ValueError: return False

def valid_ssh_public_key(key: str) -> bool:
    m = KEY_RE.match(key.strip())
    if not m: return False
    try:
        blob = base64.b64decode(m.group("blob"), validate=False)
    except Exception:
        return False
    return 30 <= len(blob) <= 16384


class VMInfo(BaseModel):
    vm_name: str
    ip_address: str
    port: int = 22
    username: str
    public_key: Optional[str] = None
    machine_guid: Optional[str] = None
    all_ips: Optional[List[str]] = None

    @field_validator("vm_name")
    @classmethod
    def _v_name(cls, v):
        if not v or not NAME_RE.match(v): raise ValueError("vm_name invalid")
        return v

    @field_validator("username")
    @classmethod
    def _v_user(cls, v):
        if not v or not USER_RE.match(v): raise ValueError("username invalid")
        return v

    @field_validator("ip_address")
    @classmethod
    def _v_ip(cls, v):
        if not valid_ip(v): raise ValueError("ip invalid")
        return v.strip()

    @field_validator("port")
    @classmethod
    def _v_port(cls, v):
        if not (1 <= v <= 65535): raise ValueError("port invalid")
        return v

    @field_validator("machine_guid")
    @classmethod
    def _v_guid(cls, v):
        if v is None or not v.strip(): return None
        if len(v) > 128: raise ValueError("guid too long")
        return v.strip()

    @field_validator("public_key")
    @classmethod
    def _v_key(cls, v):
        if v is None or not v.strip(): return None
        if not valid_ssh_public_key(v): raise ValueError("public_key invalid")
        return v.strip()

    @field_validator("all_ips")
    @classmethod
    def _v_ips(cls, v):
        if v is None: return v
        if len(v) > 20: raise ValueError("too many ips")
        return [ip.strip() for ip in v if valid_ip(ip)]


class KeyIn(BaseModel):
    public_key: str
    @field_validator("public_key")
    @classmethod
    def _v_key(cls, v):
        v = v.strip()
        if not valid_ssh_public_key(v): raise ValueError("public_key invalid")
        return v


def env_keys():
    res = []
    for line in re.split(r"[\r\n,]+", os.environ.get("AUTHORIZED_KEYS", "")):
        s = line.strip()
        if s and not s.startswith("#") and KEY_RE.match(s) and s not in res:
            res.append(s)
    return res

def all_keys():
    res = env_keys()
    if keys_col is not None:
        try:
            for d in keys_col.find({}, {"_id": 1}):
                if KEY_RE.match(d["_id"]) and d["_id"] not in res:
                    res.append(d["_id"])
        except PyMongoError: pass
    return res


@app.get("/health")
def health():
    info = {"status": "ok", "time": now().isoformat(timespec="seconds")}
    if client:
        try:
            client.admin.command("ping")
            info["db"] = "ok"
            info["vms"] = vms.estimated_document_count()
        except PyMongoError as e:
            info["db"] = f"error:{e}"
    else:
        info["db"] = "not_configured"
    return info

@app.get("/api/authorized-keys")
def get_keys():
    db_guard()
    return {"keys": all_keys()}

@app.post("/api/vms")
def register_vm(vm: VMInfo):
    db_guard()
    doc = vm.model_dump()
    doc["updated_at"] = now()
    try:
        vms.update_one(
            {"_id": vm.vm_name},
            {"$set": doc, "$setOnInsert": {"first_seen": now()}},
            upsert=True,
        )
    except PyMongoError:
        raise HTTPException(503, "db_error")
    return {"status": "success", "vm": vm.vm_name}

@app.delete("/api/vms/{vm_name}")
def delete_vm(vm_name: str):
    db_guard()
    r = vms.delete_one({"_id": vm_name})
    if r.deleted_count == 0: raise HTTPException(404, "not_found")
    return {"status": "success"}

@app.post("/api/authorized-keys")
def add_key(k: KeyIn, req: Request):
    require_admin(req); db_guard()
    keys_col.update_one({"_id": k.public_key}, {"$setOnInsert": {"added_at": now()}}, upsert=True)
    return {"status": "success", "total_keys": len(all_keys())}

@app.delete("/api/authorized-keys")
def del_key(k: KeyIn, req: Request):
    require_admin(req); db_guard()
    r = keys_col.delete_one({"_id": k.public_key})
    if r.deleted_count == 0: raise HTTPException(404, "not_found")
    return {"status": "success"}
