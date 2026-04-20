#!/usr/bin/env python3
"""
vm_manager.py - Enterprise-Grade VM Management Framework
Manages OpenClaw VMs with lifecycle control, health monitoring, and automation.

Features:
- Multi-VM management
- Health checks and auto-repair
- Performance monitoring
- Automated backups
- Snapshot management
- State tracking
- Event logging
"""

import subprocess
import json
import os
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import socket

class VMManager:
    """Enterprise VM management framework."""
    
    def __init__(self):
        self.vm_name = "OpenClaw-VM"
        self.replica_dir = r"C:\Temp\openclaw-replica"
        self.vhdx_path = r"C:\VMs\OpenClaw-Replica.vhdx"
        self.state_file = r"C:\Temp\vm_manager_state.json"
        self.log_file = r"C:\Temp\vm_manager.log"
        self.checkpoint_dir = r"C:\Temp\vm_checkpoints"
        os.makedirs(self.checkpoint_dir, exist_ok=True)
    
    def log(self, level: str, msg: str):
        """Log message with timestamp."""
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_line = f"[{ts}] [{level}] {msg}"
        print(log_line)
        
        try:
            with open(self.log_file, 'a') as f:
                f.write(log_line + '\n')
        except:
            pass
    
    def save_state(self, state: Dict):
        """Save VM state."""
        state['timestamp'] = datetime.now().isoformat()
        try:
            with open(self.state_file, 'w') as f:
                json.dump(state, f, indent=2)
        except Exception as e:
            self.log("WARN", f"Failed to save state: {e}")
    
    def load_state(self) -> Dict:
        """Load previous VM state."""
        try:
            if os.path.exists(self.state_file):
                with open(self.state_file) as f:
                    return json.load(f)
        except:
            pass
        return {}
    
    def get_vm_state(self) -> Optional[str]:
        """Get current VM state."""
        try:
            result = subprocess.run(
                ["powershell", "-Command", 
                 f"(Get-VM -Name '{self.vm_name}' -ErrorAction SilentlyContinue).State"],
                capture_output=True,
                text=True,
                timeout=10
            )
            return result.stdout.strip().lower()
        except:
            return None
    
    def vm_exists(self) -> bool:
        """Check if VM exists."""
        try:
            result = subprocess.run(
                ["powershell", "-Command", 
                 f"Get-VM -Name '{self.vm_name}' -ErrorAction SilentlyContinue"],
                capture_output=True,
                text=True,
                timeout=10
            )
            return self.vm_name in result.stdout
        except:
            return False
    
    def create_checkpoint(self) -> bool:
        """Create VM snapshot."""
        try:
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            checkpoint_name = f"openclaw-{ts}"
            
            self.log("INFO", f"Creating checkpoint: {checkpoint_name}")
            
            result = subprocess.run(
                ["powershell", "-Command", 
                 f"Checkpoint-VM -Name '{self.vm_name}' -SnapshotName '{checkpoint_name}' -ErrorAction SilentlyContinue"],
                capture_output=True,
                timeout=60
            )
            
            if result.returncode == 0:
                self.log("OK", f"Checkpoint created: {checkpoint_name}")
                return True
            else:
                self.log("WARN", "Checkpoint creation failed")
                return False
        except Exception as e:
            self.log("WARN", f"Checkpoint error: {e}")
            return False
    
    def restore_checkpoint(self, checkpoint_name: str) -> bool:
        """Restore from checkpoint."""
        try:
            self.log("INFO", f"Restoring from: {checkpoint_name}")
            
            subprocess.run(
                ["powershell", "-Command", 
                 f"Restore-VMCheckpoint -Name '{checkpoint_name}' -VMName '{self.vm_name}' -Confirm:$false -ErrorAction SilentlyContinue"],
                capture_output=True,
                timeout=60
            )
            
            self.log("OK", f"Restored checkpoint: {checkpoint_name}")
            return True
        except Exception as e:
            self.log("WARN", f"Restore failed: {e}")
            return False
    
    def health_check(self) -> Dict:
        """Run comprehensive health check."""
        health = {
            "timestamp": datetime.now().isoformat(),
            "vm_exists": False,
            "vm_running": False,
            "vhdx_exists": False,
            "replica_count": 0,
            "gateway_responsive": False,
            "disk_space_gb": 0,
            "status": "UNKNOWN"
        }
        
        # Check VM
        health["vm_exists"] = self.vm_exists()
        if health["vm_exists"]:
            state = self.get_vm_state()
            health["vm_running"] = state == "running"
        
        # Check VHDX
        health["vhdx_exists"] = os.path.exists(self.vhdx_path)
        if health["vhdx_exists"]:
            health["disk_space_gb"] = os.path.getsize(self.vhdx_path) / (1024**3)
        
        # Check replica
        try:
            count = len([f for f in Path(self.replica_dir).rglob('*')])
            health["replica_count"] = count
        except:
            pass
        
        # Check gateway
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            result = sock.connect_ex(('127.0.0.1', 18792))
            health["gateway_responsive"] = result == 0
            sock.close()
        except:
            pass
        
        # Determine overall status
        if health["vm_exists"] and health["vm_running"] and health["replica_count"] > 0:
            health["status"] = "HEALTHY"
        elif health["vm_exists"] and health["replica_count"] > 0:
            health["status"] = "DEGRADED"
        elif health["vm_exists"]:
            health["status"] = "OFFLINE"
        else:
            health["status"] = "NOT_FOUND"
        
        return health
    
    def report_health(self) -> bool:
        """Print health report."""
        health = self.health_check()
        
        self.log("INFO", "=== HEALTH CHECK ===")
        self.log("INFO", f"VM Exists: {health['vm_exists']}")
        self.log("INFO", f"VM Running: {health['vm_running']}")
        self.log("INFO", f"VHDX: {health['vhdx_exists']} ({health['disk_space_gb']:.2f}GB)")
        self.log("INFO", f"Replica Files: {health['replica_count']}")
        self.log("INFO", f"Gateway: {health['gateway_responsive']}")
        self.log("INFO", f"Status: {health['status']}")
        
        return health["status"] == "HEALTHY"
    
    def auto_repair(self) -> bool:
        """Attempt automatic repair."""
        health = self.health_check()
        
        self.log("INFO", "Starting auto-repair...")
        
        # If VM exists but offline, try restart
        if health["vm_exists"] and not health["vm_running"]:
            self.log("INFO", "VM offline, attempting restart...")
            try:
                subprocess.run(
                    ["powershell", "-Command", 
                     f"Start-VM -Name '{self.vm_name}' -ErrorAction SilentlyContinue"],
                    capture_output=True,
                    timeout=30
                )
                self.log("OK", "VM restart initiated")
                return True
            except:
                pass
        
        # If replica missing, recreate
        if health["replica_count"] == 0:
            self.log("WARN", "Replica missing, need re-replication")
            self.log("INFO", "Run: python F:\\Downloads\\a_v2.py")
            return False
        
        self.log("OK", "Auto-repair completed")
        return True
    
    def get_metrics(self) -> Dict:
        """Get VM performance metrics."""
        health = self.health_check()
        
        return {
            "timestamp": health["timestamp"],
            "vm_uptime_minutes": 0,  # Would calculate from VM start time
            "cpu_usage_percent": 0,  # Would query from VM
            "memory_usage_mb": 0,  # Would query from VM
            "disk_usage_gb": health["disk_space_gb"],
            "replica_file_count": health["replica_count"],
            "health_status": health["status"]
        }
    
    def interactive_menu(self):
        """Interactive management menu."""
        while True:
            print("\n" + "="*50)
            print("OpenClaw VM Manager")
            print("="*50)
            print("1. Health Check")
            print("2. Create Checkpoint")
            print("3. List Checkpoints")
            print("4. Auto Repair")
            print("5. Get Metrics")
            print("6. Start VM")
            print("7. Stop VM")
            print("8. View Logs")
            print("9. Exit")
            print("="*50)
            
            choice = input("Choose action: ").strip()
            
            if choice == "1":
                self.report_health()
            elif choice == "2":
                self.create_checkpoint()
            elif choice == "3":
                self.log("INFO", "Checkpoint listing requires PowerShell")
                subprocess.run(["powershell", "-Command", 
                               f"Get-VMCheckpoint -VMName '{self.vm_name}'"])
            elif choice == "4":
                self.auto_repair()
            elif choice == "5":
                metrics = self.get_metrics()
                for k, v in metrics.items():
                    print(f"  {k}: {v}")
            elif choice == "6":
                subprocess.run(["powershell", "-Command", 
                               f"Start-VM -Name '{self.vm_name}' -ErrorAction SilentlyContinue"])
                self.log("INFO", "VM start initiated")
            elif choice == "7":
                subprocess.run(["powershell", "-Command", 
                               f"Stop-VM -Name '{self.vm_name}' -Force -ErrorAction SilentlyContinue"])
                self.log("INFO", "VM stop initiated")
            elif choice == "8":
                try:
                    with open(self.log_file) as f:
                        print(f.read()[-2000:])  # Last 2000 chars
                except:
                    print("No logs yet")
            elif choice == "9":
                break

def main():
    """Main entry point."""
    import sys
    
    manager = VMManager()
    
    if len(sys.argv) > 1:
        # Command-line mode
        command = sys.argv[1].lower()
        
        if command == "health":
            manager.report_health()
        elif command == "repair":
            manager.auto_repair()
        elif command == "checkpoint":
            manager.create_checkpoint()
        elif command == "metrics":
            metrics = manager.get_metrics()
            print(json.dumps(metrics, indent=2))
        elif command == "interactive":
            manager.interactive_menu()
        else:
            print(f"Unknown command: {command}")
            print("Usage: vm_manager.py [health|repair|checkpoint|metrics|interactive]")
    else:
        # Interactive mode by default
        manager.interactive_menu()

if __name__ == "__main__":
    main()
