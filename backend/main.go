package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
)

type Response struct {
	Message     string            `json:"message"`
	Environment string            `json:"environment"`
	Version     string            `json:"version"`
	Timestamp   time.Time         `json:"timestamp"`
	Headers     map[string]string `json:"headers,omitempty"`
}

type HealthResponse struct {
	Status      string    `json:"status"`
	Environment string    `json:"environment"`
	Version     string    `json:"version"`
	Timestamp   time.Time `json:"timestamp"`
	Database    string    `json:"database"`
	Uptime      string    `json:"uptime"`
}

var (
	environment = getEnv("ENVIRONMENT", "unknown")
	version     = getEnv("VERSION", "v1.0.0")
	startTime   = time.Now()
	db          *sql.DB
)

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func initDB() {
	var err error
	dbHost := getEnv("DB_HOST", "postgres-service")
	dbPort := getEnv("DB_PORT", "5432")
	dbUser := getEnv("DB_USER", "postgres")
	dbPassword := getEnv("DB_PASSWORD", "postgres123")
	dbName := getEnv("DB_NAME", "webapp")

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		dbHost, dbPort, dbUser, dbPassword, dbName)

	log.Printf("Connecting to database: %s@%s:%s/%s", dbUser, dbHost, dbPort, dbName)

	for i := 0; i < 30; i++ {
		db, err = sql.Open("postgres", connStr)
		if err != nil {
			log.Printf("Database connection attempt %d failed: %v", i+1, err)
			time.Sleep(2 * time.Second)
			continue
		}

		err = db.Ping()
		if err != nil {
			log.Printf("Database ping attempt %d failed: %v", i+1, err)
			time.Sleep(2 * time.Second)
			continue
		}

		log.Println("Successfully connected to database")
		break
	}

	if err != nil {
		log.Printf("Failed to connect to database after 30 attempts: %v", err)
		// Don't exit, allow health checks to show database is unavailable
	}

	// Create a simple table for demonstration
	if db != nil {
		createTableSQL := `
		CREATE TABLE IF NOT EXISTS visits (
			id SERIAL PRIMARY KEY,
			environment VARCHAR(50),
			version VARCHAR(50),
			timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			ip_address VARCHAR(45)
		);`

		_, err = db.Exec(createTableSQL)
		if err != nil {
			log.Printf("Failed to create visits table: %v", err)
		} else {
			log.Println("Visits table ready")
		}
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	dbStatus := "healthy"
	if db == nil {
		dbStatus = "unavailable"
	} else {
		err := db.Ping()
		if err != nil {
			dbStatus = "unhealthy: " + err.Error()
		}
	}

	uptime := time.Since(startTime).String()

	response := HealthResponse{
		Status:      "healthy",
		Environment: environment,
		Version:     version,
		Timestamp:   time.Now(),
		Database:    dbStatus,
		Uptime:      uptime,
	}

	// Set HTTP status based on database health
	if dbStatus != "healthy" {
		w.WriteHeader(http.StatusServiceUnavailable)
		response.Status = "unhealthy"
	}

	json.NewEncoder(w).Encode(response)
}

func apiHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	// Record visit in database
	if db != nil {
		clientIP := r.Header.Get("X-Forwarded-For")
		if clientIP == "" {
			clientIP = r.Header.Get("X-Real-IP")
		}
		if clientIP == "" {
			clientIP = r.RemoteAddr
		}

		_, err := db.Exec("INSERT INTO visits (environment, version, ip_address) VALUES ($1, $2, $3)",
			environment, version, clientIP)
		if err != nil {
			log.Printf("Failed to record visit: %v", err)
		}
	}

	// Collect headers for debugging
	headers := make(map[string]string)
	for name, values := range r.Header {
		if len(values) > 0 {
			headers[name] = values[0]
		}
	}

	response := Response{
		Message:     fmt.Sprintf("Hello from %s environment!", environment),
		Environment: environment,
		Version:     version,
		Timestamp:   time.Now(),
		Headers:     headers,
	}

	json.NewEncoder(w).Encode(response)
}

func versionHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	response := map[string]interface{}{
		"environment": environment,
		"version":     version,
		"timestamp":   time.Now(),
		"uptime":      time.Since(startTime).String(),
	}

	json.NewEncoder(w).Encode(response)
}

func visitsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	if db == nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"error": "Database unavailable"})
		return
	}

	rows, err := db.Query("SELECT environment, version, timestamp, ip_address FROM visits ORDER BY timestamp DESC LIMIT 100")
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	defer rows.Close()

	var visits []map[string]interface{}
	for rows.Next() {
		var env, ver, ip string
		var timestamp time.Time

		err := rows.Scan(&env, &ver, &timestamp, &ip)
		if err != nil {
			continue
		}

		visits = append(visits, map[string]interface{}{
			"environment": env,
			"version":     ver,
			"timestamp":   timestamp,
			"ip_address":  ip,
		})
	}

	response := map[string]interface{}{
		"visits":       visits,
		"total_visits": len(visits),
		"environment":  environment,
		"version":      version,
	}

	json.NewEncoder(w).Encode(response)
}

func main() {
	log.Printf("Starting backend server - Environment: %s, Version: %s", environment, version)

	// Initialize database connection
	initDB()

	// Setup routes
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/api/status", apiHandler)
	http.HandleFunc("/api/version", versionHandler)
	http.HandleFunc("/api/visits", visitsHandler)

	// Catch-all for API routes
	http.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"message":     "API endpoint",
			"environment": environment,
			"version":     version,
			"path":        r.URL.Path,
			"method":      r.Method,
		})
	})

	port := getEnv("PORT", "8080")
	log.Printf("Server listening on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}