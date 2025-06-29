const express = require('express');
const cors = require('cors');
const multer = require('multer');
const fs = require('fs-extra');
const path = require('path');
const https = require('https');
const bodyParser = require('body-parser');
const compression = require('compression');
const helmet = require('helmet');

const app = express();
const HTTP_PORT = process.env.HTTP_PORT || 8080;
const HTTPS_PORT = process.env.HTTPS_PORT || 8443;

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '50mb' }));

// Cloud storage paths
const CLOUD_PATHS = {
    onedrive: process.env.ONEDRIVE_PATH || '/cloud-storage/OneDrive',
    googledrive: process.env.GOOGLEDRIVE_PATH || '/cloud-storage/GoogleDrive',
    dropbox: process.env.DROPBOX_PATH || '/cloud-storage/Dropbox'
};

// Ensure cloud directories exist
Object.values(CLOUD_PATHS).forEach(cloudPath => {
    fs.ensureDirSync(cloudPath);
    fs.ensureDirSync(path.join(cloudPath, 'WindowsMelodyRecovery'));
});

// Configure multer for file uploads
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const provider = req.params.provider || 'onedrive';
        const uploadPath = path.join(CLOUD_PATHS[provider], 'WindowsMelodyRecovery');
        fs.ensureDirSync(uploadPath);
        cb(null, uploadPath);
    },
    filename: (req, file, cb) => {
        cb(null, file.originalname);
    }
});

const upload = multer({ 
    storage: storage,
    limits: {
        fileSize: 100 * 1024 * 1024 // 100MB limit
    }
});

// Logging middleware
app.use((req, res, next) => {
    console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);
    next();
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        providers: {
            onedrive: fs.existsSync(CLOUD_PATHS.onedrive),
            googledrive: fs.existsSync(CLOUD_PATHS.googledrive),
            dropbox: fs.existsSync(CLOUD_PATHS.dropbox)
        }
    });
});

// Generic cloud provider status
app.get('/api/:provider/status', (req, res) => {
    const provider = req.params.provider;
    const cloudPath = CLOUD_PATHS[provider];
    
    if (!cloudPath || !fs.existsSync(cloudPath)) {
        return res.status(404).json({
            provider: provider,
            available: false,
            error: 'Provider not found or path does not exist'
        });
    }
    
    try {
        const stats = fs.statSync(cloudPath);
        const files = fs.readdirSync(cloudPath);
        
        res.json({
            provider: provider,
            available: true,
            path: cloudPath,
            created: stats.birthtime,
            modified: stats.mtime,
            fileCount: files.length,
            files: files.slice(0, 10) // First 10 files
        });
    } catch (error) {
        res.status(500).json({
            provider: provider,
            available: false,
            error: error.message
        });
    }
});

// List files in cloud storage
app.get('/api/:provider/files', (req, res) => {
    const provider = req.params.provider;
    const cloudPath = CLOUD_PATHS[provider];
    const subPath = req.query.path || '';
    
    if (!cloudPath) {
        return res.status(404).json({ error: 'Provider not found' });
    }
    
    try {
        const fullPath = path.join(cloudPath, subPath);
        
        if (!fs.existsSync(fullPath)) {
            return res.status(404).json({ error: 'Path not found' });
        }
        
        const items = fs.readdirSync(fullPath).map(item => {
            const itemPath = path.join(fullPath, item);
            const stats = fs.statSync(itemPath);
            
            return {
                name: item,
                path: path.join(subPath, item),
                type: stats.isDirectory() ? 'directory' : 'file',
                size: stats.size,
                created: stats.birthtime,
                modified: stats.mtime
            };
        });
        
        res.json({
            provider: provider,
            path: subPath,
            items: items
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Upload file to cloud storage
app.post('/api/:provider/upload', upload.single('file'), (req, res) => {
    const provider = req.params.provider;
    
    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
    }
    
    try {
        res.json({
            provider: provider,
            filename: req.file.filename,
            originalname: req.file.originalname,
            size: req.file.size,
            path: req.file.path,
            uploaded: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Upload multiple files
app.post('/api/:provider/upload-multiple', upload.array('files', 10), (req, res) => {
    const provider = req.params.provider;
    
    if (!req.files || req.files.length === 0) {
        return res.status(400).json({ error: 'No files uploaded' });
    }
    
    try {
        const uploadedFiles = req.files.map(file => ({
            filename: file.filename,
            originalname: file.originalname,
            size: file.size,
            path: file.path
        }));
        
        res.json({
            provider: provider,
            filesUploaded: uploadedFiles.length,
            files: uploadedFiles,
            uploaded: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Download file from cloud storage
app.get('/api/:provider/download/:filename', (req, res) => {
    const provider = req.params.provider;
    const filename = req.params.filename;
    const cloudPath = CLOUD_PATHS[provider];
    
    if (!cloudPath) {
        return res.status(404).json({ error: 'Provider not found' });
    }
    
    try {
        const filePath = path.join(cloudPath, 'WindowsMelodyRecovery', filename);
        
        if (!fs.existsSync(filePath)) {
            return res.status(404).json({ error: 'File not found' });
        }
        
        res.download(filePath, filename);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Delete file from cloud storage
app.delete('/api/:provider/delete/:filename', (req, res) => {
    const provider = req.params.provider;
    const filename = req.params.filename;
    const cloudPath = CLOUD_PATHS[provider];
    
    if (!cloudPath) {
        return res.status(404).json({ error: 'Provider not found' });
    }
    
    try {
        const filePath = path.join(cloudPath, 'WindowsMelodyRecovery', filename);
        
        if (!fs.existsSync(filePath)) {
            return res.status(404).json({ error: 'File not found' });
        }
        
        fs.unlinkSync(filePath);
        
        res.json({
            provider: provider,
            filename: filename,
            deleted: true,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Create directory in cloud storage
app.post('/api/:provider/mkdir', (req, res) => {
    const provider = req.params.provider;
    const dirName = req.body.name;
    const cloudPath = CLOUD_PATHS[provider];
    
    if (!cloudPath) {
        return res.status(404).json({ error: 'Provider not found' });
    }
    
    if (!dirName) {
        return res.status(400).json({ error: 'Directory name required' });
    }
    
    try {
        const dirPath = path.join(cloudPath, 'WindowsMelodyRecovery', dirName);
        fs.ensureDirSync(dirPath);
        
        res.json({
            provider: provider,
            directory: dirName,
            path: dirPath,
            created: true,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Sync status endpoint (simulates cloud sync)
app.get('/api/:provider/sync-status', (req, res) => {
    const provider = req.params.provider;
    
    // Simulate sync status
    const syncStatus = {
        provider: provider,
        status: 'synced',
        lastSync: new Date().toISOString(),
        pendingFiles: 0,
        syncedFiles: Math.floor(Math.random() * 100) + 50,
        errors: []
    };
    
    // Randomly simulate sync issues for testing
    if (Math.random() < 0.1) {
        syncStatus.status = 'syncing';
        syncStatus.pendingFiles = Math.floor(Math.random() * 5) + 1;
    }
    
    res.json(syncStatus);
});

// Backup management endpoints
app.get('/api/:provider/backups', (req, res) => {
    const provider = req.params.provider;
    const cloudPath = CLOUD_PATHS[provider];
    const backupPath = path.join(cloudPath, 'WindowsMelodyRecovery');
    
    try {
        if (!fs.existsSync(backupPath)) {
            return res.json({
                provider: provider,
                backups: []
            });
        }
        
        const backups = fs.readdirSync(backupPath)
            .filter(item => {
                const itemPath = path.join(backupPath, item);
                return fs.statSync(itemPath).isDirectory();
            })
            .map(backup => {
                const backupDir = path.join(backupPath, backup);
                const stats = fs.statSync(backupDir);
                const files = fs.readdirSync(backupDir);
                
                return {
                    name: backup,
                    created: stats.birthtime,
                    modified: stats.mtime,
                    fileCount: files.length,
                    size: files.reduce((total, file) => {
                        try {
                            const filePath = path.join(backupDir, file);
                            return total + fs.statSync(filePath).size;
                        } catch {
                            return total;
                        }
                    }, 0)
                };
            })
            .sort((a, b) => new Date(b.created) - new Date(a.created));
        
        res.json({
            provider: provider,
            backups: backups
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Error handling middleware
app.use((error, req, res, next) => {
    console.error('Server error:', error);
    res.status(500).json({
        error: 'Internal server error',
        message: error.message,
        timestamp: new Date().toISOString()
    });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({
        error: 'Endpoint not found',
        path: req.url,
        method: req.method,
        timestamp: new Date().toISOString()
    });
});

// Start HTTP server
const httpServer = app.listen(HTTP_PORT, () => {
    console.log(`Cloud Mock Server (HTTP) listening on port ${HTTP_PORT}`);
    console.log(`Available providers: ${Object.keys(CLOUD_PATHS).join(', ')}`);
    console.log(`Health check: http://localhost:${HTTP_PORT}/health`);
});

// Start HTTPS server if certificates exist
try {
    const httpsOptions = {
        key: fs.readFileSync('/app/certs/key.pem'),
        cert: fs.readFileSync('/app/certs/cert.pem')
    };
    
    const httpsServer = https.createServer(httpsOptions, app);
    httpsServer.listen(HTTPS_PORT, () => {
        console.log(`Cloud Mock Server (HTTPS) listening on port ${HTTPS_PORT}`);
    });
} catch (error) {
    console.log('HTTPS server not started (certificates not found)');
}

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('Received SIGTERM, shutting down gracefully');
    httpServer.close(() => {
        console.log('HTTP server closed');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log('Received SIGINT, shutting down gracefully');
    httpServer.close(() => {
        console.log('HTTP server closed');
        process.exit(0);
    });
}); 