/**
 * GRID: Production App Landing Page Controller
 * Handles mobile drawer, live mesh canvas simulation, voice waveform player,
 * and protocol byte inspector.
 */

document.addEventListener('DOMContentLoaded', () => {

  // ==========================================================================
  // 1. Mobile Menu Drawer Controller
  // ==========================================================================
  const mobileToggle = document.getElementById('mobileMenuToggle');
  const mobileDrawer = document.getElementById('mobileDrawer');
  const mobileNavItems = document.querySelectorAll('.mobile-nav-item');

  function openMobileMenu() {
    if (!mobileDrawer || !mobileToggle) return;
    mobileDrawer.classList.add('open');
    mobileToggle.classList.add('active');
    mobileToggle.setAttribute('aria-expanded', 'true');
    document.body.style.overflow = 'hidden';
  }

  function closeMobileMenu() {
    if (!mobileDrawer || !mobileToggle) return;
    mobileDrawer.classList.remove('open');
    mobileToggle.classList.remove('active');
    mobileToggle.setAttribute('aria-expanded', 'false');
    document.body.style.overflow = '';
  }

  if (mobileToggle) {
    mobileToggle.addEventListener('click', (e) => {
      e.stopPropagation();
      if (mobileDrawer && mobileDrawer.classList.contains('open')) {
        closeMobileMenu();
      } else {
        openMobileMenu();
      }
    });
  }

  // Close mobile drawer when any link inside is tapped
  mobileNavItems.forEach(item => {
    item.addEventListener('click', () => {
      closeMobileMenu();
    });
  });

  // Close when tapping outside
  window.addEventListener('click', (e) => {
    if (mobileDrawer && mobileDrawer.classList.contains('open')) {
      if (!mobileDrawer.contains(e.target) && !mobileToggle.contains(e.target)) {
        closeMobileMenu();
      }
    }
  });

  // Close on Escape key
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      closeMobileMenu();
    }
  });

  // ==========================================================================
  // 2. Real-Time BLE Mesh Canvas Simulator (Mouse & Touch Enabled)
  // ==========================================================================
  const canvas = document.getElementById('meshCanvas');
  const simLog = document.getElementById('simLog');
  const btnSendPacket = document.getElementById('btnSendPacket');
  const btnCutCellular = document.getElementById('btnCutCellular');
  const cutCellularText = document.getElementById('cutCellularText');
  const btnDispatchMule = document.getElementById('btnDispatchMule');
  const btnResetTopology = document.getElementById('btnResetTopology');

  if (canvas) {
    const ctx = canvas.getContext('2d');
    let width, height;

    function resize() {
      const rect = canvas.parentElement.getBoundingClientRect();
      width = rect.width;
      height = rect.height || 480;
      canvas.width = width * window.devicePixelRatio;
      canvas.height = height * window.devicePixelRatio;
      ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
    }
    window.addEventListener('resize', resize);
    resize();

    // Default Node Topology
    let nodes = [
      { id: 'node-local', name: 'Node (You)', x: 0.16, y: 0.5, role: 'source', peers: [] },
      { id: 'node-r1', name: 'Relay 01', x: 0.36, y: 0.32, role: 'relay', peers: [] },
      { id: 'node-r2', name: 'Relay 02', x: 0.42, y: 0.68, role: 'relay', peers: [] },
      { id: 'node-r3', name: 'Relay 03', x: 0.65, y: 0.42, role: 'relay', peers: [] },
      { id: 'node-dest', name: 'Bob (Peer)', x: 0.86, y: 0.55, role: 'dest', peers: [] },
      { id: 'node-iso', name: 'Shelter Alpha', x: 0.88, y: 0.85, role: 'isolated', peers: [] }
    ];

    let courier = { active: false, x: 0.42, y: 0.68, targetNode: 'node-iso', progress: 0 };
    let packets = [];
    let isCellularSevered = false;
    let draggedNode = null;

    function logTelemetry(msg, type = 'info') {
      if (!simLog) return;
      const time = new Date().toTimeString().split(' ')[0];
      const color = type === 'alert' ? '#f43f5e' : (type === 'success' ? '#22c55e' : '#38bdf8');
      const entry = document.createElement('div');
      entry.style.color = color;
      entry.innerHTML = `[${time}] ${msg}`;
      simLog.appendChild(entry);
      simLog.scrollTop = simLog.scrollHeight;
    }

    function computeLinks() {
      const maxRange = 0.36;
      nodes.forEach(n => n.peers = []);
      for (let i = 0; i < nodes.length; i++) {
        for (let j = i + 1; j < nodes.length; j++) {
          const dx = nodes[i].x - nodes[j].x;
          const dy = nodes[i].y - nodes[j].y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < maxRange && nodes[i].role !== 'isolated' && nodes[j].role !== 'isolated') {
            nodes[i].peers.push(nodes[j]);
            nodes[j].peers.push(nodes[i]);
          }
        }
      }
    }

    function draw() {
      ctx.clearRect(0, 0, width, height);

      computeLinks();

      // Draw Radio Links
      ctx.lineWidth = 2;
      for (let i = 0; i < nodes.length; i++) {
        const u = nodes[i];
        for (let v of u.peers) {
          if (u.id < v.id) {
            ctx.strokeStyle = 'rgba(34, 197, 94, 0.22)';
            ctx.beginPath();
            ctx.moveTo(u.x * width, u.y * height);
            ctx.lineTo(v.x * width, v.y * height);
            ctx.stroke();
          }
        }
      }

      // Draw Packets
      for (let i = packets.length - 1; i >= 0; i--) {
        const p = packets[i];
        p.progress += 0.035;
        if (p.progress >= 1) {
          p.currentHopIndex++;
          if (p.currentHopIndex < p.path.length - 1) {
            p.progress = 0;
            p.from = p.path[p.currentHopIndex];
            p.to = p.path[p.currentHopIndex + 1];
            p.ttl--;
            logTelemetry(`Hop #${p.currentHopIndex} relay: ${p.from.name} -> ${p.to.name} (TTL: ${p.ttl})`);
          } else {
            logTelemetry(`✓ Delivered to destination ${p.to.name}! Reverse acknowledgment received.`, 'success');
            packets.splice(i, 1);
            continue;
          }
        }

        const curX = (p.from.x + (p.to.x - p.from.x) * p.progress) * width;
        const curY = (p.from.y + (p.to.y - p.from.y) * p.progress) * height;

        ctx.fillStyle = '#38bdf8';
        ctx.shadowColor = '#38bdf8';
        ctx.shadowBlur = 14;
        ctx.beginPath();
        ctx.arc(curX, curY, 6, 0, Math.PI * 2);
        ctx.fill();
        ctx.shadowBlur = 0;
      }

      // Draw Delay-Tolerant Courier Mule
      if (courier.active) {
        courier.progress += 0.008;
        const start = nodes.find(n => n.id === 'node-r2');
        const target = nodes.find(n => n.id === 'node-iso');
        if (courier.progress >= 1) {
          courier.active = false;
          logTelemetry(`✓ Courier mule reached ${target.name}. 3 air-gapped voice notes synchronized!`, 'success');
        } else {
          const cx = (start.x + (target.x - start.x) * courier.progress) * width;
          const cy = (start.y + (target.y - start.y) * courier.progress) * height;

          ctx.fillStyle = '#f59e0b';
          ctx.beginPath();
          ctx.arc(cx, cy, 8, 0, Math.PI * 2);
          ctx.fill();

          ctx.fillStyle = '#ffffff';
          ctx.font = '11px "JetBrains Mono", monospace';
          ctx.fillText('📦 Mule', cx + 12, cy + 4);
        }
      }

      // Draw Nodes
      nodes.forEach(n => {
        const nx = n.x * width;
        const ny = n.y * height;

        ctx.fillStyle = n.role === 'source' ? '#22c55e' : (n.role === 'dest' ? '#06b6d4' : (n.role === 'isolated' ? '#64748b' : '#a855f7'));
        ctx.beginPath();
        ctx.arc(nx, ny, 16, 0, Math.PI * 2);
        ctx.fill();

        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 2;
        ctx.stroke();

        ctx.fillStyle = '#ffffff';
        ctx.font = 'bold 11px "Inter", sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText(n.name, nx, ny + 28);
      });

      requestAnimationFrame(draw);
    }

    draw();

    // Mouse Drag Handling
    canvas.addEventListener('mousedown', (e) => {
      const rect = canvas.getBoundingClientRect();
      const mx = (e.clientX - rect.left) / width;
      const my = (e.clientY - rect.top) / height;

      nodes.forEach(n => {
        const dx = n.x - mx;
        const dy = n.y - my;
        if (Math.sqrt(dx * dx + dy * dy) < 0.05) {
          draggedNode = n;
        }
      });
    });

    window.addEventListener('mousemove', (e) => {
      if (!draggedNode) return;
      const rect = canvas.getBoundingClientRect();
      draggedNode.x = Math.max(0.08, Math.min(0.92, (e.clientX - rect.left) / width));
      draggedNode.y = Math.max(0.08, Math.min(0.92, (e.clientY - rect.top) / height));
    });

    window.addEventListener('mouseup', () => {
      draggedNode = null;
    });

    // Touch Drag Handling (Mobile Devices)
    canvas.addEventListener('touchstart', (e) => {
      if (e.touches.length === 1) {
        const touch = e.touches[0];
        const rect = canvas.getBoundingClientRect();
        const mx = (touch.clientX - rect.left) / width;
        const my = (touch.clientY - rect.top) / height;

        nodes.forEach(n => {
          const dx = n.x - mx;
          const dy = n.y - my;
          if (Math.sqrt(dx * dx + dy * dy) < 0.08) {
            draggedNode = n;
            e.preventDefault();
          }
        });
      }
    }, { passive: false });

    window.addEventListener('touchmove', (e) => {
      if (!draggedNode || e.touches.length !== 1) return;
      const touch = e.touches[0];
      const rect = canvas.getBoundingClientRect();
      draggedNode.x = Math.max(0.08, Math.min(0.92, (touch.clientX - rect.left) / width));
      draggedNode.y = Math.max(0.08, Math.min(0.92, (touch.clientY - rect.top) / height));
      e.preventDefault();
    }, { passive: false });

    window.addEventListener('touchend', () => {
      draggedNode = null;
    });

    // Button: Transmit Packet
    if (btnSendPacket) {
      btnSendPacket.addEventListener('click', () => {
        const source = nodes.find(n => n.id === 'node-local');
        const dest = nodes.find(n => n.id === 'node-dest');
        if (!source || !dest) return;

        // Shortest Path BFS
        const queue = [[source]];
        const visited = new Set([source.id]);
        let shortestPath = null;

        while (queue.length > 0) {
          const path = queue.shift();
          const cur = path[path.length - 1];
          if (cur.id === dest.id) {
            shortestPath = path;
            break;
          }
          for (let neighbor of cur.peers) {
            if (!visited.has(neighbor.id)) {
              visited.add(neighbor.id);
              queue.push([...path, neighbor]);
            }
          }
        }

        if (shortestPath && shortestPath.length > 1) {
          logTelemetry(`🚀 Transmitting BitchatPacket from ${source.name} to ${dest.name} across ${shortestPath.length - 1} hops.`);
          packets.push({
            path: shortestPath,
            currentHopIndex: 0,
            from: shortestPath[0],
            to: shortestPath[1],
            progress: 0,
            ttl: 5
          });
        } else {
          logTelemetry(`⚠ No active RF link found between ${source.name} and ${dest.name}. Drag nodes closer to form a route!`, 'alert');
        }
      });
    }

    // Button: Cut Cellular
    if (btnCutCellular) {
      btnCutCellular.addEventListener('click', () => {
        isCellularSevered = !isCellularSevered;
        if (isCellularSevered) {
          btnCutCellular.style.background = '#ef4444';
          btnCutCellular.style.color = '#ffffff';
          if (cutCellularText) cutCellularText.textContent = 'Cellular Severed (OFFLINE)';
          logTelemetry('🚨 SIMULATED OUTAGE: All cellular towers and internet backbones offline. BLE Mesh remains 100% operational.', 'alert');
        } else {
          btnCutCellular.style.background = '';
          btnCutCellular.style.color = '';
          if (cutCellularText) cutCellularText.textContent = 'Cut Cellular & ISP';
          logTelemetry('Cellular infrastructure link restored to standby.', 'info');
        }
      });
    }

    // Button: Dispatch Mule
    if (btnDispatchMule) {
      btnDispatchMule.addEventListener('click', () => {
        if (courier.active) return;
        courier.active = true;
        courier.progress = 0;
        logTelemetry('📦 Dispatching delay-tolerant courier node to Shelter Alpha...', 'info');
      });
    }

    // Button: Reset
    if (btnResetTopology) {
      btnResetTopology.addEventListener('click', () => {
        nodes = [
          { id: 'node-local', name: 'Node (You)', x: 0.16, y: 0.5, role: 'source', peers: [] },
          { id: 'node-r1', name: 'Relay 01', x: 0.36, y: 0.32, role: 'relay', peers: [] },
          { id: 'node-r2', name: 'Relay 02', x: 0.42, y: 0.68, role: 'relay', peers: [] },
          { id: 'node-r3', name: 'Relay 03', x: 0.65, y: 0.42, role: 'relay', peers: [] },
          { id: 'node-dest', name: 'Bob (Peer)', x: 0.86, y: 0.55, role: 'dest', peers: [] },
          { id: 'node-iso', name: 'Shelter Alpha', x: 0.88, y: 0.85, role: 'isolated', peers: [] }
        ];
        packets = [];
        courier.active = false;
        logTelemetry('Topology reset to benchmark state.', 'info');
      });
    }
  }

  // ==========================================================================
  // 3. Tactile Audio Waveform Scrubber Demo
  // ==========================================================================
  const waveformContainer = document.getElementById('waveformContainer');
  const btnPlayVoice = document.getElementById('btnPlayVoice');
  const playIcon = document.getElementById('playIcon');
  const pauseIcon = document.getElementById('pauseIcon');
  const audioTime = document.getElementById('audioTime');
  const speedButtons = document.querySelectorAll('.btn-speed');

  let isAudioPlaying = false;
  let audioProgress = 0;
  let audioSpeed = 1.0;
  let audioInterval = null;

  if (waveformContainer) {
    waveformContainer.innerHTML = '';
    const heights = [20, 35, 60, 45, 80, 95, 70, 40, 60, 85, 90, 75, 50, 65, 85, 100, 80, 40, 30, 55, 70, 90, 65, 45, 60, 75, 85, 95, 70, 50, 40, 65, 80, 50, 35, 20];
    heights.forEach((h, idx) => {
      const bar = document.createElement('div');
      bar.className = 'wave-bar';
      bar.style.height = `${h}%`;
      bar.addEventListener('click', () => {
        audioProgress = idx / heights.length;
        updateWaveformUI();
      });
      waveformContainer.appendChild(bar);
    });
  }

  function updateWaveformUI() {
    const bars = document.querySelectorAll('.wave-bar');
    const playedCount = Math.floor(audioProgress * bars.length);
    bars.forEach((bar, idx) => {
      if (idx < playedCount) {
        bar.classList.add('played');
      } else {
        bar.classList.remove('played');
      }
    });

    const totalSec = 7;
    const curSec = Math.min(totalSec, Math.floor(audioProgress * totalSec));
    if (audioTime) {
      audioTime.textContent = `00:0${curSec} / 00:07`;
    }
  }

  if (btnPlayVoice) {
    btnPlayVoice.addEventListener('click', () => {
      isAudioPlaying = !isAudioPlaying;
      if (isAudioPlaying) {
        if (playIcon) playIcon.style.display = 'none';
        if (pauseIcon) pauseIcon.style.display = 'block';
        startPlayback();
      } else {
        if (playIcon) playIcon.style.display = 'block';
        if (pauseIcon) pauseIcon.style.display = 'none';
        clearInterval(audioInterval);
      }
    });
  }

  function startPlayback() {
    clearInterval(audioInterval);
    const stepTime = 100 / audioSpeed;
    audioInterval = setInterval(() => {
      audioProgress += 0.015;
      if (audioProgress >= 1) {
        audioProgress = 0;
        isAudioPlaying = false;
        clearInterval(audioInterval);
        if (playIcon) playIcon.style.display = 'block';
        if (pauseIcon) pauseIcon.style.display = 'none';
      }
      updateWaveformUI();
    }, stepTime);
  }

  speedButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      speedButtons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      audioSpeed = parseFloat(btn.dataset.speed) || 1.0;
      if (isAudioPlaying) {
        startPlayback();
      }
    });
  });

  // ==========================================================================
  // 4. BitChat v2.0 Protocol Byte Inspector
  // ==========================================================================
  const inspectorTabs = document.querySelectorAll('.inspector-tab');
  const inspectorDisplay = document.getElementById('inspectorDisplay');

  const inspectorData = {
    header: [
      { name: 'Magic Bytes', val: '0x42 0x43 ("BC")', desc: 'BitChat identifier' },
      { name: 'Version', val: '0x02', desc: 'Protocol version 2.0' },
      { name: 'Message Type', val: '0x01 (Direct)', desc: '1: Direct, 2: Channel, 3: Voice' },
      { name: 'Hop TTL', val: '0x05', desc: 'Degree-adaptive time-to-live' },
      { name: 'Flags', val: '0x03', desc: 'Bit 0: Encrypted, Bit 1: Voice' },
      { name: 'Session Nonce', val: '0x7F2A...C3', desc: 'ChaCha20 IV (8 bytes)' },
      { name: 'Payload Len', val: '0x01A4 (420B)', desc: 'Ciphertext length' },
      { name: 'Header CRC', val: '0x9E21', desc: 'CRC-16 integrity check' }
    ],
    handshake: [
      { name: 'Noise Pattern', val: 'XX', desc: 'Mutual key authentication' },
      { name: 'Ephemeral PubKey', val: '32 Bytes (e)', desc: 'Curve25519 ephemeral key' },
      { name: 'Encrypted Static', val: '48 Bytes (s)', desc: 'ChaCha20 static identity key' },
      { name: 'Poly1305 MAC', val: '16 Bytes', desc: 'AEAD authentication tag' }
    ],
    voice: [
      { name: 'Voice Header', val: '0x56 0x4F ("VO")', desc: 'Voice payload indicator' },
      { name: 'Slice Index', val: '0x04 / 0x20', desc: 'Fragment 4 of 32' },
      { name: 'Opus Bitrate', val: '16 kbps CBR', desc: 'Ultra-low bandwidth speech' },
      { name: 'Voice Payload', val: '440 Bytes', desc: 'Opus encoded voice slice' },
      { name: 'Slice CRC', val: '0x8F3A', desc: 'Frame integrity verification' }
    ]
  };

  function renderInspector(tabKey) {
    if (!inspectorDisplay || !inspectorData[tabKey]) return;
    inspectorDisplay.innerHTML = '';
    inspectorData[tabKey].forEach(item => {
      const block = document.createElement('div');
      block.className = 'byte-block';
      block.innerHTML = `
        <strong>${item.name}</strong>
        <div style="color: #22c55e; margin: 4px 0;">${item.val}</div>
        <span>${item.desc}</span>
      `;
      inspectorDisplay.appendChild(block);
    });
  }

  inspectorTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      inspectorTabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      renderInspector(tab.dataset.tab);
    });
  });

  renderInspector('header');

  // ==========================================================================
  // 5. Terminal Quickstart Copy Button
  // ==========================================================================
  const btnCopyTerminal = document.getElementById('btnCopyTerminal');
  const terminalCode = document.getElementById('terminalCode');

  if (btnCopyTerminal && terminalCode) {
    btnCopyTerminal.addEventListener('click', () => {
      navigator.clipboard.writeText(terminalCode.innerText);
      btnCopyTerminal.textContent = 'Copied!';
      setTimeout(() => {
        btnCopyTerminal.textContent = 'Copy';
      }, 2000);
    });
  }

});
