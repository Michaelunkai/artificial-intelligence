# CI/CD Integration Guide - OpenClaw VM Automation

This guide shows how to integrate the OpenClaw VM automation into your CI/CD pipeline (GitHub Actions, Azure DevOps, Jenkins, etc.).

---

## 🚀 GitHub Actions Integration

### **Step 1: Create Workflow File**

Create `.github/workflows/vm-deploy.yml`:

```yaml
name: Deploy OpenClaw VM

on:
  push:
    branches: [ main, develop ]
  workflow_dispatch:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  deploy-vm:
    runs-on: windows-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Create OpenClaw VM
        run: python a_v2.py
        working-directory: .\Downloads
      
      - name: Verify VM
        run: |
          powershell -ExecutionPolicy Bypass -File test_vm.ps1
        working-directory: .\Downloads
      
      - name: Health Check
        run: python vm_manager.py health
        working-directory: .\Downloads
      
      - name: Generate Report
        if: always()
        run: |
          echo "## VM Deployment Report" >> $env:GITHUB_STEP_SUMMARY
          echo "- VM: OpenClaw-VM" >> $env:GITHUB_STEP_SUMMARY
          echo "- Status: Complete" >> $env:GITHUB_STEP_SUMMARY

  stress-test:
    runs-on: windows-latest
    needs: deploy-vm
    
    steps:
      - name: Run 10-iteration stress test
        run: |
          powershell -ExecutionPolicy Bypass -File batch_test.ps1 -Runs 10
        working-directory: .\Downloads
```

---

## 🔵 Azure DevOps Integration

### **Step 1: Create Pipeline YAML**

Create `azure-pipelines.yml`:

```yaml
trigger:
  - main
  - develop

schedules:
  - cron: "0 2 * * *"
    displayName: Daily VM Deployment
    branches:
      include:
        - main

pool:
  vmImage: 'windows-latest'

stages:
  - stage: Deploy
    displayName: 'Deploy VM'
    jobs:
      - job: CreateVM
        displayName: 'Create OpenClaw VM'
        steps:
          - task: UsePythonVersion@0
            inputs:
              versionSpec: '3.11'
              addToPath: true
          
          - script: |
              python a_v2.py
            displayName: 'Create VM'
            workingDirectory: '$(System.DefaultWorkingDirectory)\Downloads'
          
          - script: |
              powershell -ExecutionPolicy Bypass -File test_vm.ps1
            displayName: 'Validate VM'
            workingDirectory: '$(System.DefaultWorkingDirectory)\Downloads'
          
          - script: |
              python vm_manager.py health
            displayName: 'Health Check'
            workingDirectory: '$(System.DefaultWorkingDirectory)\Downloads'
          
          - task: PublishBuildArtifacts@1
            condition: always()
            inputs:
              PathtoPublish: '$(System.DefaultWorkingDirectory)\Temp'
              ArtifactName: 'vm-logs'

  - stage: Test
    displayName: 'Stress Test'
    dependsOn: Deploy
    condition: succeeded()
    jobs:
      - job: StressTest
        displayName: 'Run Batch Tests'
        steps:
          - script: |
              powershell -ExecutionPolicy Bypass -File batch_test.ps1 -Runs 10
            displayName: 'Stress Test (10 runs)'
            workingDirectory: '$(System.DefaultWorkingDirectory)\Downloads'
```

---

## 🔨 Jenkins Integration

### **Jenkinsfile**

```groovy
pipeline {
    agent { label 'windows' }
    
    triggers {
        pollSCM('H 2 * * *')  // Daily at 2 AM
        githubPush()
    }
    
    stages {
        stage('Create VM') {
            steps {
                bat '''
                    python a_v2.py
                '''
            }
        }
        
        stage('Validate') {
            steps {
                powershell '''
                    powershell -ExecutionPolicy Bypass -File test_vm.ps1
                '''
            }
        }
        
        stage('Health Check') {
            steps {
                bat '''
                    python vm_manager.py health
                '''
            }
        }
        
        stage('Stress Test') {
            steps {
                powershell '''
                    powershell -ExecutionPolicy Bypass -File batch_test.ps1 -Runs 5
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'C:\\Temp\\vm_manager.log'
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
        failure {
            emailext(
                subject: "VM Deployment Failed",
                body: "Check Jenkins logs for details",
                to: 'team@example.com'
            )
        }
    }
}
```

---

## 📦 GitLab CI Integration

### **.gitlab-ci.yml**

```yaml
stages:
  - deploy
  - test
  - monitor

variables:
  PYTHON_VERSION: "3.11"

deploy_vm:
  stage: deploy
  image: mcr.microsoft.com/windows/servercore:ltsc2022
  script:
    - python a_v2.py
    - powershell -ExecutionPolicy Bypass -File test_vm.ps1
  only:
    - main
    - develop
  schedule:
    - cron: "0 2 * * *"

stress_test:
  stage: test
  image: mcr.microsoft.com/windows/servercore:ltsc2022
  script:
    - powershell -ExecutionPolicy Bypass -File batch_test.ps1 -Runs 10
  needs: ["deploy_vm"]
  artifacts:
    paths:
      - C:\Temp\vm_manager.log
    expire_in: 30 days

health_monitor:
  stage: monitor
  image: mcr.microsoft.com/windows/servercore:ltsc2022
  script:
    - python vm_manager.py health
  schedule:
    - cron: "*/5 * * * *"
```

---

## 🔄 Continuous Deployment Pipeline

### **Multi-Environment Workflow**

```yaml
# GitHub Actions Example
name: Multi-Environment VM Deploy

on:
  push:
    branches: [ main ]
    paths:
      - 'a_v2.py'
      - 'b.py'

jobs:
  dev-deploy:
    runs-on: windows-latest
    environment:
      name: development
    steps:
      - uses: actions/checkout@v3
      - run: python a_v2.py
      - run: powershell -ExecutionPolicy Bypass -File test_vm.ps1

  staging-deploy:
    runs-on: windows-latest
    needs: dev-deploy
    environment:
      name: staging
    steps:
      - uses: actions/checkout@v3
      - run: python a_v2.py
      - run: python vm_manager.py checkpoint
      - run: powershell -ExecutionPolicy Bypass -File batch_test.ps1 -Runs 5

  production-deploy:
    runs-on: windows-latest
    needs: staging-deploy
    environment:
      name: production
    steps:
      - uses: actions/checkout@v3
      - run: python a_v2.py
      - run: python vm_manager.py health
```

---

## 📊 Monitoring & Alerts

### **Health Check Monitoring**

```python
# monitoring.py
import subprocess
import json
import smtplib
from email.mime.text import MIMEText

def send_alert(subject, body):
    """Send email alert on failure."""
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = 'vm-monitor@example.com'
    msg['To'] = 'team@example.com'
    
    with smtplib.SMTP('smtp.example.com') as server:
        server.send_message(msg)

def monitor_health():
    """Monitor VM health and alert on issues."""
    result = subprocess.run(
        ["python", "vm_manager.py", "metrics"],
        capture_output=True,
        text=True
    )
    
    metrics = json.loads(result.stdout)
    
    if metrics['health_status'] != 'HEALTHY':
        send_alert(
            "⚠️ VM Health Issue",
            f"Status: {metrics['health_status']}\n\nMetrics:\n{json.dumps(metrics, indent=2)}"
        )

if __name__ == "__main__":
    monitor_health()
```

---

## 🚀 Deployment Checklist

Before deploying to production CI/CD:

- [ ] Test locally: `python a_v2.py`
- [ ] Run health check: `python vm_manager.py health`
- [ ] Run stress test: `powershell -ExecutionPolicy Bypass -File batch_test.ps1 -Runs 10`
- [ ] Verify logs: Check `C:\Temp\vm_manager.log`
- [ ] Configure CI/CD secrets (if needed)
- [ ] Set up monitoring/alerts
- [ ] Test rollback procedure
- [ ] Document runbook for ops team

---

## 📋 Runbook - Emergency Procedures

### **VM Crashed**
```bash
python vm_manager.py auto_repair
```

### **Restore from Checkpoint**
```bash
python vm_manager.py restore <checkpoint_name>
```

### **Full Redeployment**
```bash
Stop-VM -Name "OpenClaw-VM" -Force
Remove-VM -Name "OpenClaw-VM" -Force
python a_v2.py
```

---

## 🎯 Best Practices

1. **Schedule deployments** during off-peak hours
2. **Run stress tests** to verify reliability before production
3. **Monitor health** continuously with vm_manager.py
4. **Create checkpoints** before major changes
5. **Log everything** to audit trail
6. **Alert on failures** via email/Slack
7. **Test rollback** procedures regularly
8. **Document** all customizations

---

## 📞 Support

For issues:
1. Check logs: `cat C:\Temp\vm_manager.log`
2. Run health check: `python vm_manager.py health`
3. Review CI/CD pipeline output
4. Contact ops team with logs

---

**Your OpenClaw VM automation is now enterprise-ready for CI/CD integration!**

