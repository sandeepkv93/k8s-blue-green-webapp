import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [status, setStatus] = useState(null);
  const [visits, setVisits] = useState([]);
  const [loading, setLoading] = useState(true);
  const [lastUpdate, setLastUpdate] = useState(new Date());

  const environment = process.env.REACT_APP_ENVIRONMENT || 'unknown';
  const version = process.env.REACT_APP_VERSION || 'v1.0.0';
  const apiUrl = process.env.REACT_APP_API_URL || '';

  const fetchStatus = async () => {
    try {
      const response = await fetch(`${apiUrl}/api/status`);
      const data = await response.json();
      setStatus(data);
    } catch (error) {
      console.error('Failed to fetch status:', error);
      setStatus({ error: 'Failed to connect to backend' });
    }
  };

  const fetchVisits = async () => {
    try {
      const response = await fetch(`${apiUrl}/api/visits`);
      const data = await response.json();
      setVisits(data.visits || []);
    } catch (error) {
      console.error('Failed to fetch visits:', error);
    }
  };

  const refreshData = async () => {
    setLoading(true);
    await Promise.all([fetchStatus(), fetchVisits()]);
    setLastUpdate(new Date());
    setLoading(false);
  };

  useEffect(() => {
    refreshData();
    const interval = setInterval(refreshData, 30000); // Refresh every 30 seconds
    return () => clearInterval(interval);
  }, []);

  const getEnvironmentColor = () => {
    return environment === 'blue' ? '#007bff' : 
           environment === 'green' ? '#28a745' : '#6c757d';
  };

  const getEnvironmentIcon = () => {
    return environment === 'blue' ? '🔵' : 
           environment === 'green' ? '🟢' : '⚫';
  };

  return (
    <div className="App">
      <header className="App-header" style={{ backgroundColor: getEnvironmentColor() }}>
        <h1>
          {getEnvironmentIcon()} Blue-Green Deployment Demo
        </h1>
        <div className="environment-info">
          <span className="environment-badge">
            Environment: {environment.toUpperCase()}
          </span>
          <span className="version-badge">
            Version: {version}
          </span>
        </div>
      </header>

      <main className="App-main">
        <div className="container">
          <div className="status-section">
            <div className="card">
              <h2>Backend Status</h2>
              {loading ? (
                <div className="loading">Loading...</div>
              ) : status ? (
                <div className="status-info">
                  {status.error ? (
                    <div className="error">{status.error}</div>
                  ) : (
                    <>
                      <p><strong>Message:</strong> {status.message}</p>
                      <p><strong>Backend Environment:</strong> 
                        <span className={`env-badge env-${status.environment}`}>
                          {status.environment}
                        </span>
                      </p>
                      <p><strong>Backend Version:</strong> {status.version}</p>
                      <p><strong>Timestamp:</strong> {new Date(status.timestamp).toLocaleString()}</p>
                    </>
                  )}
                </div>
              ) : (
                <div className="error">No data available</div>
              )}
              
              <button onClick={refreshData} className="refresh-btn" disabled={loading}>
                {loading ? 'Refreshing...' : 'Refresh'}
              </button>
            </div>
          </div>

          <div className="visits-section">
            <div className="card">
              <h2>Recent Visits</h2>
              <p>Last updated: {lastUpdate.toLocaleString()}</p>
              
              {visits.length > 0 ? (
                <div className="visits-list">
                  <table>
                    <thead>
                      <tr>
                        <th>Environment</th>
                        <th>Version</th>
                        <th>Timestamp</th>
                        <th>IP Address</th>
                      </tr>
                    </thead>
                    <tbody>
                      {visits.slice(0, 10).map((visit, index) => (
                        <tr key={index}>
                          <td>
                            <span className={`env-badge env-${visit.environment}`}>
                              {visit.environment}
                            </span>
                          </td>
                          <td>{visit.version}</td>
                          <td>{new Date(visit.timestamp).toLocaleString()}</td>
                          <td>{visit.ip_address}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {visits.length > 10 && (
                    <p className="more-visits">
                      ... and {visits.length - 10} more visits
                    </p>
                  )}
                </div>
              ) : (
                <div className="no-visits">No visits recorded yet</div>
              )}
            </div>
          </div>

          <div className="info-section">
            <div className="card">
              <h2>About This Demo</h2>
              <p>
                This application demonstrates a blue-green deployment strategy using Kubernetes.
                The frontend and backend can be deployed to different environments (blue/green)
                and traffic can be switched instantly between them.
              </p>
              
              <h3>Key Features:</h3>
              <ul>
                <li>Zero-downtime deployments</li>
                <li>Instant traffic switching</li>
                <li>Environment isolation</li>
                <li>Shared database across environments</li>
                <li>Health monitoring and rollback capabilities</li>
              </ul>

              <h3>Current Configuration:</h3>
              <ul>
                <li><strong>Frontend Environment:</strong> {environment}</li>
                <li><strong>Frontend Version:</strong> {version}</li>
                <li><strong>Backend Environment:</strong> {status?.environment || 'Unknown'}</li>
                <li><strong>Backend Version:</strong> {status?.version || 'Unknown'}</li>
              </ul>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;