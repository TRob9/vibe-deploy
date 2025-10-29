package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type GitHubWebhook struct {
	Repository struct {
		Name     string `json:"name"`
		CloneURL string `json:"clone_url"`
		HTMLURL  string `json:"html_url"`
	} `json:"repository"`
	Ref string `json:"ref"`
}

type AppType string

const (
	AppTypeStatic AppType = "static"
	AppTypeNode   AppType = "node"
	AppTypeGo     AppType = "go"
	AppTypePython AppType = "python"
)

func main() {
	http.HandleFunc("/webhook", handleWebhook)
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "OK")
	})

	log.Println("VibeDeploy webhook service (Caddy) starting on :8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal(err)
	}
}

func handleWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("Error reading body: %v", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	var webhook GitHubWebhook
	if err := json.Unmarshal(body, &webhook); err != nil {
		log.Printf("Error parsing JSON: %v", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	// Only deploy on push to main branch
	if webhook.Ref != "refs/heads/main" && webhook.Ref != "refs/heads/master" {
		log.Printf("Ignoring push to branch: %s", webhook.Ref)
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "Ignored - not main/master branch")
		return
	}

	repoName := webhook.Repository.Name
	log.Printf("Received webhook for repo: %s", repoName)

	// Deploy the site
	if err := deploySite(repoName, webhook.Repository.CloneURL); err != nil {
		log.Printf("Deployment failed: %v", err)
		http.Error(w, "Deployment failed", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "Deployed %s successfully", repoName)
}

func deploySite(repoName, cloneURL string) error {
	deployDir := filepath.Join("/deployments", repoName)
	hostDeployDir := filepath.Join("/home/thoma/Projects/vibe-deploy/deployments", repoName)

	log.Printf("Deploying %s to %s", repoName, deployDir)

	// Clone or pull the repository
	if _, err := os.Stat(deployDir); os.IsNotExist(err) {
		log.Printf("Cloning repository...")
		cmd := exec.Command("git", "clone", cloneURL, deployDir)
		if output, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("git clone failed: %v - %s", err, output)
		}
	} else {
		log.Printf("Pulling latest changes...")
		cmd := exec.Command("git", "-C", deployDir, "pull")
		if output, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("git pull failed: %v - %s", err, output)
		}
	}

	// Detect app type
	appType := detectAppType(deployDir)
	log.Printf("Detected app type: %s", appType)

	log.Printf("DNS: %s.tomtom.fyi will be routed via Cloudflare Tunnel → Caddy", repoName)

	// Deploy with Docker
	if err := deployDocker(repoName, hostDeployDir, appType); err != nil {
		return fmt.Errorf("docker deployment failed: %v", err)
	}

	// Update Caddy configuration
	if err := updateCaddyConfig(repoName, appType); err != nil {
		log.Printf("WARNING: Failed to update Caddy config: %v", err)
		// Don't fail deployment if Caddy update fails
	}

	log.Printf("Successfully deployed %s", repoName)
	return nil
}

func updateCaddyConfig(containerName string, appType AppType) error {
	domain := os.Getenv("DOMAIN")
	if domain == "" {
		domain = "tomtom.fyi"
	}

	hostname := fmt.Sprintf("%s.%s", containerName, domain)
	port := detectPort("", appType)

	log.Printf("Updating Caddy configuration for %s...", hostname)

	// Add entry to sites.yaml if not exists
	sitesYaml := "/app/sites.yaml"
	content, err := os.ReadFile(sitesYaml)
	if err != nil {
		return fmt.Errorf("failed to read sites.yaml: %v", err)
	}

	// Simple check if site already exists in config
	if !strings.Contains(string(content), hostname) {
		// Append new site
		newEntry := fmt.Sprintf("\n  %s:\n    container: %s\n    port: %s\n    type: %s\n",
			hostname, containerName, port, appType)

		f, err := os.OpenFile(sitesYaml, os.O_APPEND|os.O_WRONLY, 0644)
		if err != nil {
			return fmt.Errorf("failed to open sites.yaml: %v", err)
		}
		defer f.Close()

		if _, err := f.WriteString(newEntry); err != nil {
			return fmt.Errorf("failed to write to sites.yaml: %v", err)
		}

		log.Printf("Added %s to sites.yaml", hostname)
	}

	// Regenerate Caddyfile
	if err := generateCaddyfile(); err != nil {
		return fmt.Errorf("failed to generate Caddyfile: %v", err)
	}

	// Reload Caddy
	log.Printf("Reloading Caddy...")
	reloadCmd := exec.Command("docker", "exec", "caddy", "caddy", "reload", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile")
	if output, err := reloadCmd.CombinedOutput(); err != nil {
		return fmt.Errorf("caddy reload failed: %v - %s", err, output)
	}

	log.Printf("✓ Caddy configuration updated and reloaded")
	return nil
}

func generateCaddyfile() error {
	sitesYaml := "/app/sites.yaml"
	caddyfile := "/app/Caddyfile"

	// Read sites.yaml
	content, err := os.ReadFile(sitesYaml)
	if err != nil {
		return err
	}

	// Create Caddyfile header
	output := `# Auto-generated Caddyfile for VibeDeploy
# DO NOT EDIT MANUALLY - Managed by webhook service

{
    admin off
    auto_https off
    log {
        output file /var/log/caddy/access.log
        format json
    }
}

`

	// Parse sites.yaml (simple parser)
	lines := strings.Split(string(content), "\n")
	var currentDomain string
	var container string
	var port string

	for _, line := range lines {
		line = strings.TrimSpace(line)

		if strings.HasSuffix(line, ":") && strings.HasPrefix(line, "  ") && !strings.HasPrefix(line, "    ") {
			// This is a domain line
			if currentDomain != "" && container != "" && port != "" {
				// Write previous entry
				output += fmt.Sprintf("\n%s, www.%s {\n    reverse_proxy %s:%s\n}\n",
					currentDomain, currentDomain, container, port)
			}
			currentDomain = strings.TrimSuffix(strings.TrimSpace(line), ":")
			container = ""
			port = ""
		} else if strings.HasPrefix(line, "container:") {
			container = strings.TrimSpace(strings.TrimPrefix(line, "container:"))
		} else if strings.HasPrefix(line, "port:") {
			port = strings.TrimSpace(strings.TrimPrefix(line, "port:"))
		}
	}

	// Write last entry
	if currentDomain != "" && container != "" && port != "" {
		output += fmt.Sprintf("\n%s, www.%s {\n    reverse_proxy %s:%s\n}\n",
			currentDomain, currentDomain, container, port)
	}

	// Write Caddyfile
	if err := os.WriteFile(caddyfile, []byte(output), 0644); err != nil {
		return fmt.Errorf("failed to write Caddyfile: %v", err)
	}

	log.Printf("✓ Generated Caddyfile with %d entries", strings.Count(output, "reverse_proxy"))
	return nil
}

func detectAppType(deployDir string) AppType {
	if _, err := os.Stat(filepath.Join(deployDir, "package.json")); err == nil {
		return AppTypeNode
	}
	if _, err := os.Stat(filepath.Join(deployDir, "go.mod")); err == nil {
		return AppTypeGo
	}
	if _, err := os.Stat(filepath.Join(deployDir, "requirements.txt")); err == nil {
		return AppTypePython
	}
	if _, err := os.Stat(filepath.Join(deployDir, "main.py")); err == nil {
		return AppTypePython
	}
	return AppTypeStatic
}

func generateDockerfile(deployDir string, appType AppType) error {
	var dockerfileContent string

	switch appType {
	case AppTypeNode:
		dockerfileContent = `FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
`
	case AppTypeGo:
		dockerfileContent = `FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY . .
RUN go build -o main .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/main .
EXPOSE 8080
CMD ["./main"]
`
	case AppTypePython:
		dockerfileContent = `FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt* ./
RUN pip install --no-cache-dir -r requirements.txt || true
COPY . .
EXPOSE 8000
CMD ["python", "main.py"]
`
	default:
		return nil
	}

	dockerfilePath := filepath.Join(deployDir, "Dockerfile")
	if _, err := os.Stat(dockerfilePath); os.IsNotExist(err) {
		if err := os.WriteFile(dockerfilePath, []byte(dockerfileContent), 0644); err != nil {
			return fmt.Errorf("failed to write Dockerfile: %v", err)
		}
		log.Printf("Generated Dockerfile for %s app", appType)
	} else {
		log.Printf("Using existing Dockerfile")
	}

	return nil
}

func deployDocker(containerName, deployDir string, appType AppType) error {
	// Check if old container exists
	oldContainerExists := false
	checkCmd := exec.Command("docker", "inspect", containerName)
	if err := checkCmd.Run(); err == nil {
		oldContainerExists = true
		log.Printf("Found existing container %s", containerName)
	}

	if appType == AppTypeStatic {
		// Static sites: simple deployment
		if oldContainerExists {
			exec.Command("docker", "stop", containerName).Run()
			exec.Command("docker", "rm", containerName).Run()
		}

		// NO LABELS NEEDED! Caddy routes by container name
		cmd := exec.Command("docker", "run", "-d",
			"--name", containerName,
			"--network", "vibe-deploy_web",
			"-v", fmt.Sprintf("%s:/usr/share/nginx/html:ro", deployDir),
			"nginx:alpine",
		)

		output, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("docker run failed: %v - %s", err, output)
		}
	} else {
		// Dynamic app: zero-downtime deployment
		if err := generateDockerfile(deployDir, appType); err != nil {
			return err
		}

		imageName := fmt.Sprintf("vibe-deploy-%s:latest", containerName)
		log.Printf("Building Docker image: %s", imageName)

		buildCmd := exec.Command("docker", "build", "-t", imageName, deployDir)
		if output, err := buildCmd.CombinedOutput(); err != nil {
			log.Printf("Build failed, keeping old container running")
			return fmt.Errorf("docker build failed: %v - %s", err, output)
		}
		log.Printf("Build succeeded")

		// Test new container
		tempContainerName := containerName + "-new"
		exec.Command("docker", "stop", tempContainerName).Run()
		exec.Command("docker", "rm", tempContainerName).Run()

		cmd := exec.Command("docker", "run", "-d",
			"--name", tempContainerName,
			"--network", "vibe-deploy_web",
			imageName,
		)

		output, err := cmd.CombinedOutput()
		if err != nil {
			log.Printf("New container failed to start")
			return fmt.Errorf("docker run failed: %v - %s", err, output)
		}

		exec.Command("sleep", "2").Run()

		// Health check
		checkNewCmd := exec.Command("docker", "inspect", "-f", "{{.State.Running}}", tempContainerName)
		statusOutput, err := checkNewCmd.CombinedOutput()
		if err != nil || string(statusOutput) != "true\n" {
			log.Printf("New container failed health check")
			exec.Command("docker", "stop", tempContainerName).Run()
			exec.Command("docker", "rm", tempContainerName).Run()
			return fmt.Errorf("health check failed")
		}

		log.Printf("New container healthy, swapping...")

		// Swap containers
		if oldContainerExists {
			exec.Command("docker", "stop", containerName).Run()
			exec.Command("docker", "rm", containerName).Run()
		}

		exec.Command("docker", "stop", tempContainerName).Run()
		exec.Command("docker", "rm", tempContainerName).Run()

		// Start final container (NO LABELS!)
		finalCmd := exec.Command("docker", "run", "-d",
			"--name", containerName,
			"--network", "vibe-deploy_web",
			imageName,
		)

		finalOutput, err := finalCmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("final start failed: %v - %s", err, finalOutput)
		}
	}

	log.Printf("Container %s started successfully", containerName)
	return nil
}

func detectPort(deployDir string, appType AppType) string {
	switch appType {
	case AppTypeNode:
		return "3000"
	case AppTypeGo:
		return "8080"
	case AppTypePython:
		return "8000"
	default:
		return "80"
	}
}
