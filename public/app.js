/**
 * Grid - Decentralized Peer-to-Peer Mesh & Nostr Messenger
 * Premium Interactive Landing Page Engine
 */

document.addEventListener('DOMContentLoaded', () => {
  initNavbar();
  initMeshSimulator();
  initWaveformPlayer();
  initPacketInspector();
  initFaqAccordion();
  initCopyButtons();
  initScrollEffects();
});

/* ==========================================================================
   1. NAVIGATION & MOBILE DRAWER
   ========================================================================== */
function initNavbar() {
  const navbar = document.getElementById('navbar');
  const menuToggle = document.getElementById('mobileMenuToggle');
  const navLinks = document.getElementById('navLinks');

  window.addEventListener('scroll', () => {
    if (window.scrollY > 40) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
  });

  if (menuToggle && navLinks) {
    menuToggle.addEventListener('click', () => {
      navLinks.classList.toggle('open');
      menuToggle.classList.toggle('active');
    });

    navLinks.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', () => {
        navLinks.classList.remove('open');
        menuToggle.classList.remove('active');
      });
    });
  }
}

/* ==========================================================================
   2. INTERACTIVE MESH NETWORK SIMULATOR (HTML5 CANVAS)
   ========================================================================== */
function initMeshSimulator() {
  const canvas = document.getElementById('meshCanvas');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  let width, height;
  let animationFrameId;

  // Simulation State
  let internetCut = false;
  let courierActive = false;
  let draggedNode = null;
  let dragOffset = { x: 0, y: 0 };
  let packets = [];
  let telemetryLogs = [];

  function resize() {
    const rect = canvas.getBoundingClientRect();
    width = rect.width;
    height = rect.height;
    canvas.width = width * window.devicePixelRatio;
    canvas.height = height * window.devicePixelRatio;
    ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
  }
  window.addEventListener('resize', resize);
  resize();

  // Nodes Definition
  let nodes = [
    { id: 'node-source', name: 'Node (You)', x: 0.18, y: 0.5, role: 'source', battery: 92, peers: [] },
    { id: 'node-r1', name: 'Relay 01', x: 0.38, y: 0.32, role: 'relay', battery: 84, peers: [] },
    { id: 'node-r2', name: 'Relay 02', x: 0.42, y: 0.68, role: 'relay', battery: 76, peers: [] },
    { id: 'node-mac', name: 'MacBook Pro', x: 0.62, y: 0.45, role: 'relay', battery: 100, peers: [] },
    { id: 'node-r3', name: 'Relay 03', x: 0.78, y: 0.28, role: 'relay', battery: 65, peers: [] },
    { id: 'node-dest', name: 'Alice (Peer)', x: 0.86, y: 0.62, role: 'dest', battery: 88, peers: [] },
    // Isolated Cluster for Courier Demo
    { id: 'node-iso', name: 'Shelter Alpha', x: 0.88, y: 0.85, role: 'isolated', battery: 54, peers: [] }
  ];

  // Courier Node
  let courier = {
    id: 'node-courier',
    name: 'Courier Mule',
    x: 0.62,
    y: 0.45,
    targetIndex: 0,
    targets: [{ x: 0.62, y: 0.45 }, { x: 0.88, y: 0.85 }],
    speed: 0.003,
    carrying: false,
    active: false
  };

  // Helper to get absolute coordinates
  function getPos(node) {
    return { x: node.x * width, y: node.y * height };
  }

  // Calculate connections (BLE range: within 35% of canvas diagonal)
  function updateConnections() {
    const maxDist = Math.hypot(width, height) * 0.34;
    nodes.forEach(n1 => {
      n1.peers = [];
      nodes.forEach(n2 => {
        if (n1.id === n2.id) return;
        // If isolated cluster and courier not active, don't link with main mesh
        if ((n1.id === 'node-iso' || n2.id === 'node-iso') && !courierActive) {
          return;
        }
        const p1 = getPos(n1);
        const p2 = getPos(n2);
        const dist = Math.hypot(p1.x - p2.x, p1.y - p2.y);
        if (dist < maxDist) {
          n1.peers.push(n2);
        }
      });
    });
  }

  // Add Log Entry
  function logTelemetry(msg, type = 'info') {
    const logBox = document.getElementById('simLogs');
    if (!logBox) return;
    const time = new Date().toTimeString().split(' ')[0];
    const el = document.createElement('div');
    el.className = `log-line log-${type}`;
    el.innerHTML = `<span class="log-time">[${time}]</span> ${msg}`;
    logBox.prepend(el);
    while (logBox.children.length > 5) {
      logBox.removeChild(logBox.lastChild);
    }
  }

  // Transmit Packet
  function transmitPacket() {
    const sourceNode = nodes.find(n => n.id === 'node-source');
    const destNode = nodes.find(n => n.id === 'node-dest');
    if (!sourceNode || !destNode) return;

    // BFS Path Finding
    const queue = [[sourceNode]];
    const visited = new Set([sourceNode.id]);
    let shortestPath = null;

    while (queue.length > 0) {
      const path = queue.shift();
      const current = path[path.length - 1];

      if (current.id === destNode.id) {
        shortestPath = path;
        break;
      }

      for (let peer of current.peers) {
        if (!visited.has(peer.id)) {
          visited.add(peer.id);
          queue.push([...path, peer]);
        }
      }
    }

    if (!shortestPath || shortestPath.length < 2) {
      logTelemetry('No active BLE route found to destination.', 'error');
      return;
    }

    const pathNames = shortestPath.map(n => n.name).join(' ➔ ');
    logTelemetry(`Encrypted Packet Broadcast: ${pathNames} (TTL: ${shortestPath.length})`, 'success');

    packets.push({
      path: shortestPath,
      currentStep: 0,
      progress: 0,
      speed: 0.025,
      ttl: shortestPath.length,
      color: '#22c55e'
    });
  }

  // Canvas Interactions
  canvas.addEventListener('mousedown', (e) => {
    const rect = canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;

    nodes.forEach(node => {
      const pos = getPos(node);
      if (Math.hypot(pos.x - mouseX, pos.y - mouseY) < 26) {
        draggedNode = node;
        dragOffset.x = pos.x - mouseX;
        dragOffset.y = pos.y - mouseY;
      }
    });
  });

  window.addEventListener('mousemove', (e) => {
    if (!draggedNode) return;
    const rect = canvas.getBoundingClientRect();
    let x = (e.clientX - rect.left + dragOffset.x) / width;
    let y = (e.clientY - rect.top + dragOffset.y) / height;
    draggedNode.x = Math.max(0.05, Math.min(0.95, x));
    draggedNode.y = Math.max(0.08, Math.min(0.92, y));
  });

  window.addEventListener('mouseup', () => {
    draggedNode = null;
  });

  // Canvas Click to add custom peer
  canvas.addEventListener('dblclick', (e) => {
    const rect = canvas.getBoundingClientRect();
    const mouseX = (e.clientX - rect.left) / width;
    const mouseY = (e.clientY - rect.top) / height;
    const newId = `node-custom-${nodes.length}`;
    nodes.push({
      id: newId,
      name: `Peer #${nodes.length}`,
      x: mouseX,
      y: mouseY,
      role: 'relay',
      battery: 80,
      peers: []
    });
    logTelemetry(`Spawned new BLE mesh node: Peer #${nodes.length}`, 'info');
  });

  // Controls Handlers
  const btnTransmit = document.getElementById('btnSimTransmit');
  const btnCutInternet = document.getElementById('btnSimCutInternet');
  const btnCourier = document.getElementById('btnSimCourier');
  const btnReset = document.getElementById('btnSimReset');

  if (btnTransmit) {
    btnTransmit.addEventListener('click', () => transmitPacket());
  }

  if (btnCutInternet) {
    btnCutInternet.addEventListener('click', () => {
      internetCut = !internetCut;
      btnCutInternet.classList.toggle('active', internetCut);
      const label = document.getElementById('cloudStatusLabel');
      if (internetCut) {
        btnCutInternet.innerHTML = `<span class="icon">⚡</span> Restore Cellular / Internet`;
        if (label) label.textContent = 'CELLULAR / ISP DOWN (100% BLE MESH)';
        if (label) label.className = 'status-tag status-offline';
        logTelemetry('ISP / Cell Towers severed! Switched to zero-infrastructure BLE mesh routing.', 'warn');
      } else {
        btnCutInternet.innerHTML = `<span class="icon">✂️</span> Cut Cellular & Internet`;
        if (label) label.textContent = 'DUAL TRANSPORT: BLE MESH + NOSTR RELAYS';
        if (label) label.className = 'status-tag status-online';
        logTelemetry('Internet restored. Nostr fallback bridges active.', 'info');
      }
    });
  }

  if (btnCourier) {
    btnCourier.addEventListener('click', () => {
      courierActive = !courierActive;
      btnCourier.classList.toggle('active', courierActive);
      courier.active = courierActive;
      if (courierActive) {
        logTelemetry('Store-and-Forward Courier Mule dispatched across air gap!', 'success');
      } else {
        logTelemetry('Courier Mule returned to base.', 'info');
      }
    });
  }

  if (btnReset) {
    btnReset.addEventListener('click', () => {
      nodes = [
        { id: 'node-source', name: 'Node (You)', x: 0.18, y: 0.5, role: 'source', battery: 92, peers: [] },
        { id: 'node-r1', name: 'Relay 01', x: 0.38, y: 0.32, role: 'relay', battery: 84, peers: [] },
        { id: 'node-r2', name: 'Relay 02', x: 0.42, y: 0.68, role: 'relay', battery: 76, peers: [] },
        { id: 'node-mac', name: 'MacBook Pro', x: 0.62, y: 0.45, role: 'relay', battery: 100, peers: [] },
        { id: 'node-r3', name: 'Relay 03', x: 0.78, y: 0.28, role: 'relay', battery: 65, peers: [] },
        { id: 'node-dest', name: 'Alice (Peer)', x: 0.86, y: 0.62, role: 'dest', battery: 88, peers: [] },
        { id: 'node-iso', name: 'Shelter Alpha', x: 0.88, y: 0.85, role: 'isolated', battery: 54, peers: [] }
      ];
      packets = [];
      logTelemetry('Mesh simulation topology reset to initial state.', 'info');
    });
  }

  // Animation Loop
  let tick = 0;
  function render() {
    tick += 0.02;
    ctx.clearRect(0, 0, width, height);

    updateConnections();

    // 1. Draw Links
    nodes.forEach(n1 => {
      const p1 = getPos(n1);
      n1.peers.forEach(n2 => {
        if (n1.id < n2.id) {
          const p2 = getPos(n2);
          const dist = Math.hypot(p1.x - p2.x, p1.y - p2.y);
          const alpha = Math.max(0.12, 0.45 - (dist / (Math.hypot(width, height) * 0.34)) * 0.35);

          ctx.beginPath();
          ctx.moveTo(p1.x, p1.y);
          ctx.lineTo(p2.x, p2.y);
          ctx.strokeStyle = internetCut ? `rgba(34, 197, 94, ${alpha * 1.5})` : `rgba(6, 182, 212, ${alpha})`;
          ctx.lineWidth = 1.5;
          ctx.setLineDash([4, 4]);
          ctx.stroke();
          ctx.setLineDash([]);
        }
      });
    });

    // 2. Draw Courier if Active
    if (courier.active) {
      const target = courier.targets[courier.targetIndex];
      const dx = target.x - courier.x;
      const dy = target.y - courier.y;
      const dist = Math.hypot(dx, dy);

      if (dist < 0.02) {
        courier.targetIndex = (courier.targetIndex + 1) % courier.targets.length;
        courier.carrying = !courier.carrying;
        if (courier.carrying) {
          logTelemetry('Courier picked up stored packet for Shelter Alpha', 'warn');
        } else {
          logTelemetry('Courier delivered packet to air-gapped Shelter Alpha!', 'success');
        }
      } else {
        courier.x += (dx / dist) * courier.speed;
        courier.y += (dy / dist) * courier.speed;
      }

      const cp = getPos(courier);
      // Courier trail & halo
      ctx.beginPath();
      ctx.arc(cp.x, cp.y, 18, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(234, 179, 8, 0.15)';
      ctx.fill();

      ctx.beginPath();
      ctx.arc(cp.x, cp.y, 8, 0, Math.PI * 2);
      ctx.fillStyle = '#eab308';
      ctx.fill();

      ctx.fillStyle = '#fef08a';
      ctx.font = '10px "JetBrains Mono", monospace';
      ctx.fillText(courier.carrying ? '📦 Mule (Carrying)' : '🚶 Mule', cp.x - 24, cp.y - 14);
    }

    // 3. Draw Nodes
    nodes.forEach(node => {
      const pos = getPos(node);
      const isDragging = draggedNode && draggedNode.id === node.id;
      const isSource = node.role === 'source';
      const isDest = node.role === 'dest';
      const isIso = node.role === 'isolated';

      // Outer Pulse Ring
      const pulseSize = 14 + Math.sin(tick + pos.x) * 3;
      ctx.beginPath();
      ctx.arc(pos.x, pos.y, pulseSize + (isDragging ? 4 : 0), 0, Math.PI * 2);
      if (isSource) {
        ctx.fillStyle = 'rgba(34, 197, 94, 0.18)';
      } else if (isDest) {
        ctx.fillStyle = 'rgba(6, 182, 212, 0.2)';
      } else if (isIso) {
        ctx.fillStyle = 'rgba(234, 179, 8, 0.15)';
      } else {
        ctx.fillStyle = 'rgba(255, 255, 255, 0.06)';
      }
      ctx.fill();

      // Node Body
      ctx.beginPath();
      ctx.arc(pos.x, pos.y, 10, 0, Math.PI * 2);
      ctx.fillStyle = '#0e0e11';
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = isSource ? '#22c55e' : (isDest ? '#06b6d4' : (isIso ? '#eab308' : '#71717a'));
      ctx.stroke();

      // Inner Indicator Dot
      ctx.beginPath();
      ctx.arc(pos.x, pos.y, 4, 0, Math.PI * 2);
      ctx.fillStyle = isSource ? '#22c55e' : (isDest ? '#06b6d4' : (isIso ? '#eab308' : '#a1a1aa'));
      ctx.fill();

      // Label
      ctx.fillStyle = '#f4f4f5';
      ctx.font = '11px Inter, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(node.name, pos.x, pos.y + 24);

      // Peer Count & Battery
      ctx.fillStyle = '#71717a';
      ctx.font = '9px "JetBrains Mono", monospace';
      ctx.fillText(`${node.peers.length} peers`, pos.x, pos.y + 36);
    });

    // 4. Draw Moving Packets
    for (let i = packets.length - 1; i >= 0; i--) {
      const pkt = packets[i];
      const fromNode = pkt.path[pkt.currentStep];
      const toNode = pkt.path[pkt.currentStep + 1];

      if (!toNode) {
        // Packet reached destination
        const destPos = getPos(fromNode);
        ctx.beginPath();
        ctx.arc(destPos.x, destPos.y, 28, 0, Math.PI * 2);
        ctx.strokeStyle = '#22c55e';
        ctx.lineWidth = 2;
        ctx.stroke();
        packets.splice(i, 1);
        continue;
      }

      pkt.progress += pkt.speed;
      const p1 = getPos(fromNode);
      const p2 = getPos(toNode);
      const curX = p1.x + (p2.x - p1.x) * pkt.progress;
      const curY = p1.y + (p2.y - p1.y) * pkt.progress;

      // Draw Glowing Packet Head
      ctx.beginPath();
      ctx.arc(curX, curY, 6, 0, Math.PI * 2);
      ctx.fillStyle = pkt.color;
      ctx.shadowColor = pkt.color;
      ctx.shadowBlur = 10;
      ctx.fill();
      ctx.shadowBlur = 0;

      // TTL Badge
      ctx.fillStyle = '#ffffff';
      ctx.font = '9px "JetBrains Mono", monospace';
      ctx.fillText(`TTL:${pkt.ttl - pkt.currentStep}`, curX, curY - 10);

      if (pkt.progress >= 1) {
        pkt.progress = 0;
        pkt.currentStep++;
      }
    }

    animationFrameId = requestAnimationFrame(render);
  }

  render();
}

/* ==========================================================================
   3. INTERACTIVE AUDIO WAVEFORM PLAYER DEMO
   ========================================================================== */
function initWaveformPlayer() {
  const playBtn = document.getElementById('demoPlayBtn');
  const waveBarsContainer = document.getElementById('demoWaveBars');
  const timeDisplay = document.getElementById('demoTimeDisplay');
  const speedBtn = document.getElementById('demoSpeedBtn');
  if (!playBtn || !waveBarsContainer) return;

  let isPlaying = false;
  let currentTime = 0;
  const totalDuration = 7; // 7 seconds voice note
  let playbackSpeed = 1.0;
  let playInterval = null;

  // Generate 36 realistic waveform heights
  const heights = [
    25, 40, 70, 85, 45, 30, 60, 95, 80, 50, 65, 90,
    100, 75, 40, 60, 85, 95, 70, 45, 35, 55, 80, 60,
    30, 50, 75, 90, 65, 40, 55, 70, 45, 30, 20, 15
  ];

  waveBarsContainer.innerHTML = '';
  heights.forEach((h, idx) => {
    const bar = document.createElement('div');
    bar.className = 'wave-bar';
    bar.style.height = `${h}%`;
    bar.dataset.index = idx;
    bar.addEventListener('click', () => {
      seekTo((idx / heights.length) * totalDuration);
    });
    waveBarsContainer.appendChild(bar);
  });

  function updateBars() {
    const progress = currentTime / totalDuration;
    const activeIndex = Math.floor(progress * heights.length);
    const bars = waveBarsContainer.querySelectorAll('.wave-bar');
    bars.forEach((bar, idx) => {
      bar.classList.toggle('played', idx <= activeIndex);
    });

    const m = Math.floor(currentTime / 60).toString().padStart(2, '0');
    const s = Math.floor(currentTime % 60).toString().padStart(2, '0');
    if (timeDisplay) {
      timeDisplay.textContent = `${m}:${s} / 00:07`;
    }
  }

  function seekTo(targetTime) {
    currentTime = Math.min(totalDuration, Math.max(0, targetTime));
    updateBars();
  }

  function togglePlay() {
    isPlaying = !isPlaying;
    if (isPlaying) {
      playBtn.innerHTML = `
        <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
          <rect x="6" y="4" width="4" height="16" rx="1"></rect>
          <rect x="14" y="4" width="4" height="16" rx="1"></rect>
        </svg>
      `;
      playInterval = setInterval(() => {
        currentTime += 0.1 * playbackSpeed;
        if (currentTime >= totalDuration) {
          currentTime = 0;
          togglePlay();
        }
        updateBars();
      }, 100);
    } else {
      playBtn.innerHTML = `
        <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
          <polygon points="5 3 19 12 5 21 5 3"></polygon>
        </svg>
      `;
      if (playInterval) {
        clearInterval(playInterval);
        playInterval = null;
      }
    }
  }

  playBtn.addEventListener('click', togglePlay);

  if (speedBtn) {
    speedBtn.addEventListener('click', () => {
      if (playbackSpeed === 1.0) playbackSpeed = 1.5;
      else if (playbackSpeed === 1.5) playbackSpeed = 2.0;
      else playbackSpeed = 1.0;
      speedBtn.textContent = `${playbackSpeed.toFixed(1)}x`;
    });
  }

  updateBars();
}

/* ==========================================================================
   4. INTERACTIVE PACKET WIRE INSPECTOR
   ========================================================================== */
function initPacketInspector() {
  const tabs = document.querySelectorAll('.pkt-tab');
  const specViews = document.querySelectorAll('.pkt-spec-view');

  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const targetId = tab.dataset.target;
      tabs.forEach(t => t.classList.remove('active'));
      specViews.forEach(v => v.classList.remove('active'));

      tab.classList.add('active');
      const view = document.getElementById(targetId);
      if (view) view.classList.add('active');
    });
  });

  // Byte block tooltips
  const byteBlocks = document.querySelectorAll('.byte-block');
  const byteInfoTitle = document.getElementById('byteInfoTitle');
  const byteInfoDesc = document.getElementById('byteInfoDesc');

  byteBlocks.forEach(block => {
    block.addEventListener('mouseenter', () => {
      const title = block.dataset.field || 'Wire Field';
      const desc = block.dataset.desc || 'No details available.';
      if (byteInfoTitle) byteInfoTitle.textContent = title;
      if (byteInfoDesc) byteInfoDesc.textContent = desc;
      byteBlocks.forEach(b => b.classList.remove('selected'));
      block.classList.add('selected');
    });
  });
}

/* ==========================================================================
   5. FAQ ACCORDION
   ========================================================================== */
function initFaqAccordion() {
  const items = document.querySelectorAll('.faq-item');
  items.forEach(item => {
    const question = item.querySelector('.faq-question');
    question.addEventListener('click', () => {
      const isOpen = item.classList.contains('open');
      items.forEach(i => i.classList.remove('open'));
      if (!isOpen) item.classList.add('open');
    });
  });
}

/* ==========================================================================
   6. COPY TO CLIPBOARD BUTTONS
   ========================================================================== */
function initCopyButtons() {
  const copyBtns = document.querySelectorAll('.copy-btn');
  copyBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const text = btn.dataset.copyText || btn.previousElementSibling.textContent;
      navigator.clipboard.writeText(text.trim()).then(() => {
        const orig = btn.innerHTML;
        btn.innerHTML = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"></polyline></svg> Copied!`;
        btn.classList.add('copied');
        setTimeout(() => {
          btn.innerHTML = orig;
          btn.classList.remove('copied');
        }, 2000);
      });
    });
  });
}

/* ==========================================================================
   7. SCROLL-TRIGGERED INTERSECTION OBSERVER
   ========================================================================== */
function initScrollEffects() {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
      }
    });
  }, { threshold: 0.1 });

  document.querySelectorAll('.reveal-on-scroll').forEach(el => observer.observe(el));
}
