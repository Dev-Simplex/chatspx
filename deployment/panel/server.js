const express = require('express');
const session = require('express-session');
const http = require('http');
const { Server } = require('socket.io');
const { Client } = require('ssh2');
const { execSync } = require('child_process');
const path = require('path');

// ============================================================
// CONFIG HARDCODED
// ============================================================

const AUTH = { user: 'admin', pass: 'Jzs72144#$GSpx' };
const GITHUB_REPO = 'Dev-Simplex/chatspx';
const SESSION_SECRET = 'spx-panel-s3cr3t-k3y-2026';
const PORT = 4000;
const STATUS_INTERVAL = 60000;
const HEARTBEAT_SIZE = 60;

const SSH_KEY = `-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAjGyZwywsYUjDVYa8yyafsTpj+39b0bTN0+GgEGwi1ZQKQFGV
mdhdPr4Vf5RqAgDMvfy6zaBwJ69gJv7v8v7eC8cl8Y1sEn5Yyhk8SweIT4IzXO36
WtTm73fa3mvogmQ6eSmO/TgoacauRiZ+moyUTGpXXp1PGHnAxCBRsOHpf+ddub23
NwH39TKnKseTC377Da/fSXWXTj58oNFK3mIJIOTBImxxjzEQW7omTH9r1tKEI5tS
TAbfv6CXJrJ08+bLPL+hqNqVANuxsVrzck8+6e6re4B3Bf0D7YhuVuCl/LG/A8du
CaEnOS9pCusNBK7NhY0SguVHQupTYbNDBnvgjwIDAQABAoIBAQCFP5g4p3YFanJQ
eeY0L5ZhKjMttxB90b9uSy8D5li3qh6AIep/bdwtaVolEcP12qRts5/e91r1jWkE
F+3A+y/gpTzQFY5zjgja3U9lMuSZ7cana/qgrl3k5ip93I9pC4qg5lqU1fEjTjCY
yHZiWPtv94ioc0VWyFGuyaw62GQlxRI0h+gWC6nsmCpfDaFYnDWAVNeFRwez876E
5xjF9dyislrl+7EPH54kJQIRGY3BSC0cXRMuliQvOffdkcmtkmgPET9myPpFXT/z
XwI/VETApP5iG2Mg6H9CTDi7ziLxuKgVUd6kkTbWTRP9ZbyhmhRabGKFqLotVvmh
MO5QFoPhAoGBAMHGimE7EpZ1wffGsD+nbMkWDJBi9ytf+PgZLwaPnbrq6WEPL+3d
Kv/m3dSZpoheq4xxJp8zcCYk3/xW4JN7+AHvQznkuf+RxA+srGTPqrC87YVwhrwp
AG2xwPUarXfvo72lGZQLDkmo0jvBfIbsyik2pBccBFUanyrt4OJCeEMVAoGBALmE
Rohts3oY5YReNnH50yMtr9K4VB2rzL6SDODp0XOJlcF833OQO3V+evpzt6Xj+z1t
4bD081HLw2yX0/VlLWrDoCSuxOENtpNglYFjCjvbhcV46bx1kGMDGsvpbdI4Ntm+
eK6tpJXnr0BgoCDLxnOETpMYt3wWE8UcdUOARM4TAoGAWnYYdenA9LLGuahs8Vp0
469CcElzQDGOpiwDkxmKtg8iomgXpQDiKRMbLjwIzZL8nRTZxeqaiYQfeMsKDnAK
SMTs6mMIHfJryDGBTZLRCa85Z1kv3Tl69LrN7N7map5aH5eqyD0dD3AbrT/XpZl3
iyPyGMPAlgZWlhD1Mkt7nz0CgYEAp1/oIv6WhvofWSWHCZ3UGFEH6J3Vhk+SEf3D
EMjj59GiA0eecq0WeBL88Sml702ZRvr0PKtDO/ETB86TtTrrlv+YZIApsMKmjqD9
QhcRDKAqONe2Sgnnku0iKAcaxidhlWJ7j12quHSncPW8gtpW2bHtElmicZmZjKT4
R0ZazXECgYBQ7jK8T14wiK/DGFRSGDaS9DkPo1DmPMQifgW8uNJochy9C03OgKu9
vNDrUj26VXHayx9UYKjIANs55+D7GakBRtolOYgbtr3qvB2HKwZqqRQf8YDF5VqZ
fKAPv6FYiUrOwQkmxFO4kQdUROt6KXJpZYcWtfTdBwV4y30WA7bQQg==
-----END RSA PRIVATE KEY-----`;

const SSH_PASSWORD = 'Jzs72144#$GSpx';

const VMS = [
  { id: 'producao', name: 'PRODUCAO', ip: '192.168.8.229', user: 'simplexia', type: 'password', active: true, label: 'Proxmox' },
  { id: 'catatau', name: 'CATATAU', ip: '3.85.130.14', user: 'ubuntu', type: 'key', active: true, label: 'AWS EC2' },
  { id: 'sentinela', name: 'SENTINELA', ip: '54.166.220.138', user: 'ubuntu', type: 'key', active: true, label: 'AWS EC2' },
  { id: 'tozi', name: 'TOZI', ip: '54.91.152.38', user: 'ubuntu', type: 'key', active: false, label: 'AWS EC2' },
  { id: 'alternativo', name: 'ALTERNATIVO', ip: '192.168.8.169', user: 'simplexia', type: 'password', active: true, label: 'Proxmox' },
];

const BRANCHES = ['producao', 'homologacao', 'develop'];
const BRANCH_REGEX = /^[a-zA-Z0-9._\-/]{1,100}$/;

// ============================================================
// APP
// ============================================================

const app = express();
const server = http.createServer(app);
const io = new Server(server);

const sessionMiddleware = session({
  secret: SESSION_SECRET, resave: false, saveUninitialized: false,
  cookie: { maxAge: 4 * 60 * 60 * 1000 },
});

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(sessionMiddleware);
app.use(express.static(path.join(__dirname, 'public')));
io.engine.use(sessionMiddleware);

// ============================================================
// STATE
// ============================================================

const vmStatus = {};
const heartbeats = {};
const deployLocks = new Map();
const actionLocks = new Map();

VMS.forEach(vm => {
  vmStatus[vm.id] = { online: false, cpu: null, ram: null, disk: null, commit: null, branch: null, uptime: null, lastCheck: null, ping: null, chatwootStatus: null, chatwootStatusRaw: null, load: null, ramUsed: null, ramTotal: null, diskUsed: null, diskTotal: null, puma: null, sidekiq: null, os: null, kernel: null, cpus: null };
  heartbeats[vm.id] = [];
});

// ============================================================
// SSH
// ============================================================

function getSSHConfig(vm) {
  const config = { host: vm.ip, port: 22, username: vm.user, readyTimeout: 10000, keepaliveInterval: 5000 };
  if (vm.type === 'key') config.privateKey = SSH_KEY;
  else config.password = SSH_PASSWORD;
  return config;
}

function sshExec(vm, command, timeout = 15000) {
  return new Promise((resolve, reject) => {
    const conn = new Client();
    const timer = setTimeout(() => { conn.end(); reject(new Error('timeout')); }, timeout);
    conn.on('ready', () => {
      conn.exec(command, (err, stream) => {
        if (err) { clearTimeout(timer); conn.end(); return reject(err); }
        let stdout = '', stderr = '';
        stream.on('data', d => { stdout += d.toString(); });
        stream.stderr.on('data', d => { stderr += d.toString(); });
        stream.on('close', (code) => { clearTimeout(timer); conn.end(); resolve({ stdout: stdout.trim(), stderr: stderr.trim(), code }); });
      });
    });
    conn.on('error', err => { clearTimeout(timer); reject(err); });
    conn.connect(getSSHConfig(vm));
  });
}

function sshExecStream(vm, command, onData, onDone) {
  const conn = new Client();
  conn.on('ready', () => {
    conn.exec(command, { pty: true }, (err, stream) => {
      if (err) { conn.end(); return onDone(err); }
      stream.on('data', d => onData(d.toString()));
      stream.stderr.on('data', d => onData(d.toString()));
      stream.on('close', code => { conn.end(); onDone(null, code); });
    });
  });
  conn.on('error', err => onDone(err));
  conn.connect(getSSHConfig(vm));
  return conn;
}

// ============================================================
// STATUS CHECK - enriched metrics
// ============================================================

function buildMetricsCmd(vm) {
  const s = vm.type === 'password' ? `echo '${SSH_PASSWORD}' | sudo -S` : 'sudo';
  return [
    'echo SPX_START',
    `printf 'SPX_CPU=%s\\n' "$(LC_ALL=C top -bn1 | grep 'Cpu(s)' | awk '{printf \"%.0f\", 100-$8}')"`,
    `printf 'SPX_RAM_PCT=%s\\n' "$(free | awk '/Mem:/{printf \"%.0f\", $3/$2*100}')"`,
    `printf 'SPX_RAM_USED=%s\\n' "$(free -m | awk '/Mem:/{print $3}')"`,
    `printf 'SPX_RAM_TOTAL=%s\\n' "$(free -m | awk '/Mem:/{print $2}')"`,
    `printf 'SPX_DISK_PCT=%s\\n' "$(df / | awk 'NR==2{gsub(/%/,\"\",$5); print $5}')"`,
    `printf 'SPX_DISK_USED=%s\\n' "$(df -BG / | awk 'NR==2{gsub(/G/,\"\",$3); print $3}')"`,
    `printf 'SPX_DISK_TOTAL=%s\\n' "$(df -BG / | awk 'NR==2{gsub(/G/,\"\",$2); print $2}')"`,
    `printf 'SPX_LOAD=%s\\n' "$(cat /proc/loadavg | awk '{print $1}')"`,
    `printf 'SPX_CPUS=%s\\n' "$(nproc)"`,
    `printf 'SPX_PUMA=%s\\n' "$(pgrep -ac puma 2>/dev/null || echo 0)"`,
    `printf 'SPX_SIDEKIQ=%s\\n' "$(pgrep -ac sidekiq 2>/dev/null || echo 0)"`,
    `printf 'SPX_OS=%s\\n' "$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || echo unknown)"`,
    `printf 'SPX_KERNEL=%s\\n' "$(uname -r)"`,
    `printf 'SPX_COMMIT=%s\\n' "$(${s} -i -u chatwoot bash -c 'cd ~/chatwoot && git rev-parse --short HEAD 2>/dev/null || echo none')"`,
    `printf 'SPX_BRANCH=%s\\n' "$(${s} -i -u chatwoot bash -c 'cd ~/chatwoot && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo none')"`,
    `printf 'SPX_UPTIME=%s\\n' "$(uptime -p 2>/dev/null || echo unknown)"`,
    `printf 'SPX_SERVICE=%s\\n' "$(${s} systemctl is-active chatwoot.target 2>/dev/null || echo unknown)"`,
  ].join(' && ');
}

function parseMetrics(output) {
  const data = {};
  for (const line of output.split('\n')) {
    const m = line.match(/^SPX_(\w+)=(.*)$/);
    if (m) data[m[1]] = m[2].trim();
  }

  let uptime = data.UPTIME && data.UPTIME !== 'unknown' ? data.UPTIME : null;
  if (uptime) {
    uptime = uptime.replace(/^up\s+/, '')
      .replace(/\bdays?\b/g, 'dias').replace(/\bhours?\b/g, 'h')
      .replace(/\bminutes?\b/g, 'min').replace(/\bweeks?\b/g, 'sem')
      .replace(/,\s*/g, ', ');
  }

  const statusMap = { active: 'Ativo', inactive: 'Inativo', failed: 'Falhou', unknown: 'Desconhecido' };
  const rawStatus = data.SERVICE || 'unknown';

  return {
    cpu: Math.min(parseFloat(data.CPU) || 0, 100),
    ram: Math.min(parseFloat(data.RAM_PCT) || 0, 100),
    disk: Math.min(parseFloat(data.DISK_PCT) || 0, 100),
    ramUsed: parseInt(data.RAM_USED) || 0,
    ramTotal: parseInt(data.RAM_TOTAL) || 0,
    diskUsed: parseInt(data.DISK_USED) || 0,
    diskTotal: parseInt(data.DISK_TOTAL) || 0,
    load: data.LOAD || null,
    cpus: parseInt(data.CPUS) || null,
    puma: parseInt(data.PUMA) || 0,
    sidekiq: parseInt(data.SIDEKIQ) || 0,
    os: data.OS && data.OS !== 'unknown' ? data.OS : null,
    kernel: data.KERNEL || null,
    commit: data.COMMIT && data.COMMIT !== 'none' ? data.COMMIT : null,
    branch: data.BRANCH && data.BRANCH !== 'none' ? data.BRANCH : null,
    uptime,
    chatwootStatus: statusMap[rawStatus] || rawStatus,
    chatwootStatusRaw: rawStatus,
  };
}

async function checkVM(vm) {
  if (!vm.active) {
    vmStatus[vm.id] = { ...vmStatus[vm.id], online: false, lastCheck: new Date().toISOString(), chatwootStatus: 'Nao instalado', chatwootStatusRaw: 'not_installed' };
    addHeartbeat(vm.id, false, null, null, null);
    return;
  }

  const startTime = Date.now();
  try {
    const result = await sshExec(vm, buildMetricsCmd(vm), 14000);
    const ping = Date.now() - startTime;
    const metrics = parseMetrics(result.stdout);
    vmStatus[vm.id] = { online: true, ...metrics, lastCheck: new Date().toISOString(), ping };
    addHeartbeat(vm.id, true, ping, metrics.cpu, metrics.ram);
  } catch {
    const ping = Date.now() - startTime;
    vmStatus[vm.id] = { ...vmStatus[vm.id], online: false, lastCheck: new Date().toISOString(), ping };
    addHeartbeat(vm.id, false, ping, null, null);
  }
}

function addHeartbeat(vmId, online, ping, cpu, ram) {
  heartbeats[vmId].push({ time: new Date().toISOString(), online, ping, cpu, ram });
  if (heartbeats[vmId].length > HEARTBEAT_SIZE) heartbeats[vmId].shift();
}

function getUptimePercent(vmId) {
  const hb = heartbeats[vmId];
  if (hb.length === 0) return null;
  return ((hb.filter(h => h.online).length / hb.length) * 100).toFixed(1);
}

async function checkAllVMs() {
  await Promise.allSettled(VMS.map(vm => checkVM(vm)));
  io.emit('status:update', getPayload());
}

function getPayload() {
  return VMS.map(vm => ({
    ...vm,
    status: vmStatus[vm.id],
    heartbeat: heartbeats[vm.id],
    uptimePercent: getUptimePercent(vm.id),
    deploying: deployLocks.has(vm.id),
    actionRunning: actionLocks.has(vm.id),
  }));
}

// ============================================================
// DEPLOY
// ============================================================

function deployVM(vm, branch, socket) {
  if (deployLocks.has(vm.id)) {
    socket.emit('deploy:log', { vmId: vm.id, data: `[ERRO] Deploy ja em andamento para ${vm.name}\n` });
    return Promise.resolve();
  }
  deployLocks.set(vm.id, true);
  io.emit('deploy:lock', { vmId: vm.id, locked: true });

  return new Promise(resolve => {
    const ts = () => new Date().toLocaleTimeString('pt-BR');
    socket.emit('deploy:log', { vmId: vm.id, data: `[${ts()}] [${vm.name}] Iniciando deploy (branch: ${branch})...\n` });

    // Deploy: git pull + bundle + pnpm + assets + migrate + restart
    const s = vm.type === 'password' ? `echo '${SSH_PASSWORD}' | sudo -S` : 'sudo';
    const cmd = [
      `echo '=== ETAPA: Atualizando codigo ==='`,
      `${s} -i -u chatwoot bash -c 'cd ~/chatwoot && git stash -q 2>/dev/null; git fetch origin && git checkout ${branch} && (git pull origin ${branch} || git reset --hard origin/${branch})'`,
      `echo '=== ETAPA: Instalando dependencias Ruby ==='`,
      `${s} -i -u chatwoot bash -c 'cd ~/chatwoot && bundle install --jobs $(nproc) --retry 3 2>&1 | tail -5'`,
      `echo '=== ETAPA: Instalando dependencias JavaScript ==='`,
      `${s} -i -u chatwoot bash -c 'cd ~/chatwoot && pnpm install --frozen-lockfile 2>&1 | tail -3 || pnpm install 2>&1 | tail -3'`,
      `echo '=== ETAPA: Compilando assets ==='`,
      `${s} -i -u chatwoot bash -c 'cd ~/chatwoot && RAILS_ENV=production NODE_OPTIONS="--max-old-space-size=4096" bundle exec rake assets:precompile 2>&1 | tail -5'`,
      `echo '=== ETAPA: Migrando banco de dados ==='`,
      `${s} -i -u chatwoot bash -c 'cd ~/chatwoot && RAILS_ENV=production bundle exec rails db:migrate 2>&1 | tail -10'`,
      `echo '=== ETAPA: Reiniciando servico ==='`,
      `${s} systemctl restart chatwoot.target`,
      `echo '=== DEPLOY CONCLUIDO ==='`,
    ].join(' && ');

    sshExecStream(vm, cmd,
      data => socket.emit('deploy:log', { vmId: vm.id, data }),
      (err, code) => {
        deployLocks.delete(vm.id);
        io.emit('deploy:lock', { vmId: vm.id, locked: false });
        if (err) {
          socket.emit('deploy:log', { vmId: vm.id, data: `\n[ERRO] ${err.message}\n` });
          socket.emit('deploy:done', { vmId: vm.id, success: false, vmName: vm.name });
        } else {
          socket.emit('deploy:log', { vmId: vm.id, data: `\n[${ts()}] [${vm.name}] Finalizado (exit: ${code})\n` });
          socket.emit('deploy:done', { vmId: vm.id, success: code === 0, vmName: vm.name });
        }
        setTimeout(() => checkVM(vm).then(() => io.emit('status:update', getPayload())), 5000);
        resolve();
      }
    );
  });
}

// ============================================================
// SERVICE ACTIONS (restart, logs)
// ============================================================

function restartService(vm, service, socket) {
  const lockKey = `${vm.id}:${service}`;
  if (actionLocks.has(lockKey)) return;
  actionLocks.set(lockKey, true);

  const s = vm.type === 'password' ? `echo '${SSH_PASSWORD}' | sudo -S` : 'sudo';
  const cmd = `${s} systemctl restart ${service}`;
  const ts = () => new Date().toLocaleTimeString('pt-BR');

  socket.emit('action:log', { vmId: vm.id, data: `[${ts()}] Reiniciando ${service} em ${vm.name}...\n` });

  sshExecStream(vm, cmd,
    data => socket.emit('action:log', { vmId: vm.id, data }),
    (err, code) => {
      actionLocks.delete(lockKey);
      if (err) {
        socket.emit('action:log', { vmId: vm.id, data: `[ERRO] ${err.message}\n` });
        socket.emit('action:done', { vmId: vm.id, success: false, service });
      } else {
        socket.emit('action:log', { vmId: vm.id, data: `[${ts()}] ${service} reiniciado (exit: ${code})\n` });
        socket.emit('action:done', { vmId: vm.id, success: code === 0, service });
      }
      setTimeout(() => checkVM(vm).then(() => io.emit('status:update', getPayload())), 3000);
    }
  );
}

function viewLogs(vm, service, socket) {
  const s = vm.type === 'password' ? `echo '${SSH_PASSWORD}' | sudo -S` : 'sudo';
  const cmd = `${s} journalctl -u ${service} --no-pager -n 80 --output=short-iso`;

  socket.emit('logs:start', { vmId: vm.id, service });

  sshExecStream(vm, cmd,
    data => socket.emit('logs:data', { vmId: vm.id, data }),
    (err) => {
      if (err) socket.emit('logs:data', { vmId: vm.id, data: `[ERRO] ${err.message}\n` });
      socket.emit('logs:done', { vmId: vm.id });
    }
  );
}

// ============================================================
// AUTH & ROUTES
// ============================================================

function requireAuth(req, res, next) {
  if (req.session?.authenticated) return next();
  res.status(401).json({ error: 'Nao autenticado' });
}

app.post('/api/login', (req, res) => {
  const { user, pass } = req.body;
  if (user === AUTH.user && pass === AUTH.pass) { req.session.authenticated = true; res.json({ success: true }); }
  else res.status(401).json({ error: 'Credenciais invalidas' });
});

app.post('/api/logout', (req, res) => { req.session.destroy(); res.json({ success: true }); });
app.get('/api/status', requireAuth, (req, res) => { res.json({ vms: getPayload(), branches: BRANCHES, github: GITHUB_REPO }); });
app.get('/api/health', (req, res) => { res.json({ status: 'ok', uptime: process.uptime() }); });

// ============================================================
// SOCKET.IO
// ============================================================

io.use((socket, next) => {
  if (socket.request.session?.authenticated) return next();
  next(new Error('Nao autenticado'));
});

io.on('connection', socket => {
  socket.emit('status:update', getPayload());

  socket.on('deploy', async ({ vmIds, branch }) => {
    if (!BRANCH_REGEX.test(branch)) { socket.emit('deploy:log', { vmId: 'system', data: '[ERRO] Branch invalida\n' }); return; }
    const selected = VMS.filter(v => vmIds.includes(v.id) && v.active);
    if (!selected.length) return;
    socket.emit('deploy:start', { vmIds: selected.map(v => v.id), branch });
    for (const vm of selected) await deployVM(vm, branch, socket);
    socket.emit('deploy:allDone');
  });

  socket.on('restart', ({ vmId, service }) => {
    const vm = VMS.find(v => v.id === vmId && v.active);
    if (!vm) return;
    const allowed = ['chatwoot.target', 'chatwoot-web.1.service', 'chatwoot-worker.1.service'];
    if (!allowed.includes(service)) return;
    restartService(vm, service, socket);
  });

  socket.on('viewLogs', ({ vmId, service }) => {
    const vm = VMS.find(v => v.id === vmId && v.active);
    if (!vm) return;
    const allowed = ['chatwoot-web.1.service', 'chatwoot-worker.1.service'];
    if (!allowed.includes(service)) return;
    viewLogs(vm, service, socket);
  });

  socket.on('refresh', () => checkAllVMs());
});

// ============================================================
// START
// ============================================================

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ChatSPX Panel v3 rodando em http://0.0.0.0:${PORT}`);
  checkAllVMs();
  setInterval(checkAllVMs, STATUS_INTERVAL);
});
