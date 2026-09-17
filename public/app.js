/**
 * GRID: Brilliant.org-Inspired Interactive Active-Learning Lab
 * Master Interactive Controller
 */

document.addEventListener('DOMContentLoaded', () => {

  // ==========================================================================
  // 1. Theme Switcher (Light / Dark)
  // ==========================================================================
  const themeToggle = document.getElementById('themeToggle');
  const themeIconSun = document.getElementById('themeIconSun');
  const themeIconMoon = document.getElementById('themeIconMoon');
  const htmlRoot = document.documentElement;

  const savedTheme = localStorage.getItem('grid-theme') || 'light';
  setTheme(savedTheme);

  if (themeToggle) {
    themeToggle.addEventListener('click', () => {
      const currentTheme = htmlRoot.getAttribute('data-theme') || 'light';
      const newTheme = currentTheme === 'light' ? 'dark' : 'light';
      setTheme(newTheme);
      localStorage.setItem('grid-theme', newTheme);
    });
  }

  function setTheme(theme) {
    htmlRoot.setAttribute('data-theme', theme);
    if (theme === 'dark') {
      if (themeIconSun) themeIconSun.style.display = 'none';
      if (themeIconMoon) themeIconMoon.style.display = 'block';
    } else {
      if (themeIconSun) themeIconSun.style.display = 'block';
      if (themeIconMoon) themeIconMoon.style.display = 'none';
    }
  }

  // ==========================================================================
  // 2. Hero Micro-Challenge: "Bridge the Air Gap"
  // ==========================================================================
  const relaySlot = document.getElementById('relaySlot');
  const challengeStage = document.getElementById('challengeStage');
  const slotPlaceholder = document.getElementById('slotPlaceholder');
  const relayLabel = document.getElementById('relayLabel');
  const relaySub = document.getElementById('relaySub');
  const destNode = document.getElementById('destNode');
  const statusDot = document.getElementById('challengeStatusDot');
  const statusText = document.getElementById('challengeStatusText');
  const btnChallengeTransmit = document.getElementById('btnChallengeTransmit');

  let isRelayPlaced = false;

  if (relaySlot) {
    relaySlot.addEventListener('click', () => {
      isRelayPlaced = !isRelayPlaced;
      updateChallengeState();
    });
  }

  function updateChallengeState() {
    if (isRelayPlaced) {
      relaySlot.classList.add('placed');
      challengeStage.classList.add('connected');
      if (destNode) destNode.classList.add('active');
      if (slotPlaceholder) slotPlaceholder.innerHTML = '<span>📡 Relay</span>';
      if (relayLabel) relayLabel.textContent = 'Relay Node 01';
      if (relaySub) relaySub.textContent = 'BLE Active';
      if (statusDot) statusDot.classList.add('online');
      if (statusText) statusText.textContent = '✓ Route Verified! Alice ➔ Relay ➔ Bob (2 Hops · E2EE Active · 0ms Cloud)';
      if (btnChallengeTransmit) btnChallengeTransmit.style.display = 'inline-flex';
    } else {
      relaySlot.classList.remove('placed');
      challengeStage.classList.remove('connected');
      if (destNode) destNode.classList.remove('active');
      if (slotPlaceholder) slotPlaceholder.innerHTML = '<span>+ Deploy Relay</span>';
      if (relayLabel) relayLabel.textContent = 'Air Gap (150m)';
      if (relaySub) relaySub.textContent = 'Disconnected';
      if (statusDot) statusDot.classList.remove('online');
      if (statusText) statusText.textContent = 'Mesh network disconnected. Bluetooth signal cannot reach Bob.';
      if (btnChallengeTransmit) btnChallengeTransmit.style.display = 'none';
    }
  }

  if (btnChallengeTransmit) {
    btnChallengeTransmit.addEventListener('click', () => {
      if (!isRelayPlaced) return;
      btnChallengeTransmit.disabled = true;
      const originalText = btnChallengeTransmit.innerHTML;
      btnChallengeTransmit.innerHTML = '<span>Transmitting...</span>';

      // Visual feedback
      if (statusText) statusText.textContent = '⚡ Transmitting encrypted packet across 2 hops...';

      setTimeout(() => {
        if (statusText) statusText.textContent = '✓ Packet Delivered! Bob acknowledged receipt via reverse hop.';
        btnChallengeTransmit.innerHTML = '<span>✓ Delivered (12ms)</span>';
        setTimeout(() => {
          btnChallengeTransmit.disabled = false;
          btnChallengeTransmit.innerHTML = originalText;
          if (statusText) statusText.textContent = '✓ Route Verified! Alice ➔ Relay ➔ Bob (2 Hops · E2EE Active · 0ms Cloud)';
        }, 2000);
      }, 900);
    });
  }

  // ==========================================================================
  // 3. Module 1: Interactive BLE Mesh Canvas Simulator
  // ==========================================================================
  const canvas = document.getElementById('meshCanvas');
  const simLog = document.getElementById('simLog');
  const btnSendPacket = document.getElementById('btnSendPacket');
  const btnCutCellular = document.getElementById('btnCutCellular');
  const btnDispatchMule = document.getElementById('btnDispatchMule');
  const btnReset = document.getElementById('btnReset');

  if (canvas) {
    const ctx = canvas.getContext('2d');
    let width, height;

    function resize() {
      const rect = canvas.parentElement.getBoundingClientRect();
      width = rect.width;
      height = Math.max(rect.height, 420);
      canvas.width = width * window.devicePixelRatio;
      canvas.height = height * window.devicePixelRatio;
      ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
    }
    window.addEventListener('resize', resize);
    resize();

    // Node definitions
    let nodes = [
      { id: 'node-source', name: 'Alice (You)', x: 0.16, y: 0.5, role: 'source', peers: [] },
      { id: 'node-r1', name: 'Relay 01', x: 0.36, y: 0.32, role: 'relay', peers: [] },
      { id: 'node-r2', name: 'Relay 02', x: 0.42, y: 0.68, role: 'relay', peers: [] },
      { id: 'node-r3', name: 'Relay 03', x: 0.65, y: 0.42, role: 'relay', peers: [] },
      { id: 'node-dest', name: 'Bob (Peer)', x: 0.86, y: 0.55, role: 'dest', peers: [] },
      // Isolated node
      { id: 'node-iso', name: 'Shelter Alpha', x: 0.88, y: 0.85, role: 'isolated', peers: [] }
    ];

    let courier = { active: false, x: 0.42, y: 0.68, targetNode: 'node-iso', progress: 0 };
    let packets = [];
    let isCellularSevered = false;
    let draggedNode = null;

    function logTelemetry(msg, type = 'info') {
      if (!simLog) return;
      const time = new Date().toTimeString().split(' ')[0];
      const color = type === 'alert' ? '#f43f5e' : (type === 'success' ? '#10b981' : '#38bdf8');
      const entry = document.createElement('div');
      entry.style.color = color;
      entry.innerHTML = `[${time}] ${msg}`;
      simLog.appendChild(entry);
      simLog.scrollTop = simLog.scrollHeight;
    }

    function computeLinks() {
      const maxRange = 0.35;
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

      // Draw Links
      ctx.lineWidth = 2;
      for (let i = 0; i < nodes.length; i++) {
        const u = nodes[i];
        for (let v of u.peers) {
          if (u.id < v.id) {
            ctx.strokeStyle = 'rgba(74, 222, 128, 0.25)';
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
            logTelemetry(`Hop #${p.currentHopIndex} passed: ${p.from.name} -> ${p.to.name} (TTL: ${p.ttl})`);
          } else {
            logTelemetry(`✓ Packet Delivered to destination ${p.to.name}! Reverse ACK dispatched.`, 'success');
            packets.splice(i, 1);
            continue;
          }
        }

        const curX = (p.from.x + (p.to.x - p.from.x) * p.progress) * width;
        const curY = (p.from.y + (p.to.y - p.from.y) * p.progress) * height;

        ctx.fillStyle = '#38bdf8';
        ctx.shadowColor = '#38bdf8';
        ctx.shadowBlur = 12;
        ctx.beginPath();
        ctx.arc(curX, curY, 6, 0, Math.PI * 2);
        ctx.fill();
        ctx.shadowBlur = 0;
      }

      // Draw Courier Mule if active
      if (courier.active) {
        courier.progress += 0.008;
        const start = nodes.find(n => n.id === 'node-r2');
        const target = nodes.find(n => n.id === 'node-iso');
        if (courier.progress >= 1) {
          courier.active = false;
          logTelemetry(`✓ Courier data mule reached ${target.name}. 3 queued voice notes synced offline!`, 'success');
        } else {
          const cx = (start.x + (target.x - start.x) * courier.progress) * width;
          const cy = (start.y + (target.y - start.y) * courier.progress) * height;

          ctx.fillStyle = '#f59e0b';
          ctx.beginPath();
          ctx.arc(cx, cy, 8, 0, Math.PI * 2);
          ctx.fill();

          ctx.fillStyle = '#ffffff';
          ctx.font = '10px "JetBrains Mono"';
          ctx.fillText('📦 Mule', cx + 12, cy + 4);
        }
      }

      // Draw Nodes
      nodes.forEach(n => {
        const nx = n.x * width;
        const ny = n.y * height;

        ctx.fillStyle = n.role === 'source' ? '#10b981' : (n.role === 'dest' ? '#3b82f6' : (n.role === 'isolated' ? '#64748b' : '#a855f7'));
        ctx.beginPath();
        ctx.arc(nx, ny, 16, 0, Math.PI * 2);
        ctx.fill();

        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 2;
        ctx.stroke();

        ctx.fillStyle = '#ffffff';
        ctx.font = 'bold 11px "Plus Jakarta Sans", sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText(n.name, nx, ny + 28);
      });

      requestAnimationFrame(draw);
    }

    draw();

    // Canvas Mouse Interaction for Dragging Nodes
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

    // Button: Transmit Packet
    if (btnSendPacket) {
      btnSendPacket.addEventListener('click', () => {
        const source = nodes.find(n => n.id === 'node-source');
        const dest = nodes.find(n => n.id === 'node-dest');
        if (!source || !dest) return;

        // BFS pathfinding
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
          logTelemetry(`⚠ No active RF link found between ${source.name} and ${dest.name}. Drag nodes closer!`, 'alert');
        }
      });
    }

    // Button: Sever Cellular & ISP
    if (btnCutCellular) {
      btnCutCellular.addEventListener('click', () => {
        isCellularSevered = !isCellularSevered;
        if (isCellularSevered) {
          btnCutCellular.style.background = '#f43f5e';
          btnCutCellular.style.color = '#ffffff';
          btnCutCellular.innerHTML = '<span>⚡ Cellular Severed (OFFLINE)</span>';
          logTelemetry('🚨 SIMULATED OUTAGE: All cellular towers and internet backbones offline. BLE Mesh remains 100% operational.', 'alert');
        } else {
          btnCutCellular.style.background = '';
          btnCutCellular.style.color = '';
          btnCutCellular.innerHTML = '<span>⚡ Cut Cellular & ISP</span>';
          logTelemetry('Cellular connection restored to normal status.', 'info');
        }
      });
    }

    // Button: Dispatch Courier Mule
    if (btnDispatchMule) {
      btnDispatchMule.addEventListener('click', () => {
        if (courier.active) return;
        courier.active = true;
        courier.progress = 0;
        logTelemetry('📦 Dispatching delay-tolerant courier node to Shelter Alpha...', 'info');
      });
    }

    // Button: Reset
    if (btnReset) {
      btnReset.addEventListener('click', () => {
        nodes = [
          { id: 'node-source', name: 'Alice (You)', x: 0.16, y: 0.5, role: 'source', peers: [] },
          { id: 'node-r1', name: 'Relay 01', x: 0.36, y: 0.32, role: 'relay', peers: [] },
          { id: 'node-r2', name: 'Relay 02', x: 0.42, y: 0.68, role: 'relay', peers: [] },
          { id: 'node-r3', name: 'Relay 03', x: 0.65, y: 0.42, role: 'relay', peers: [] },
          { id: 'node-dest', name: 'Bob (Peer)', x: 0.86, y: 0.55, role: 'dest', peers: [] },
          { id: 'node-iso', name: 'Shelter Alpha', x: 0.88, y: 0.85, role: 'isolated', peers: [] }
        ];
        packets = [];
        courier.active = false;
        logTelemetry('Topology reset to default benchmark grid.', 'info');
      });
    }
  }

  // ==========================================================================
  // 4. Module 2: Noise_XX Stepper
  // ==========================================================================
  const stepButtons = document.querySelectorAll('.step-btn');
  const cryptoTitle = document.getElementById('cryptoStepTitle');
  const cryptoFormula = document.getElementById('cryptoStepFormula');
  const cryptoDesc = document.getElementById('cryptoStepDesc');

  const stepData = {
    1: {
      title: '1. Alice sends Ephemeral Public Key',
      formula: '-> e (Curve25519)',
      desc: 'Alice generates a one-time ephemeral keypair (e) and broadcasts the public key. Her static identity remains hidden; no static keys are revealed.'
    },
    2: {
      title: '2. Bob responds with Ephemeral + Encrypted Static Key',
      formula: '<- e, ee, s, es',
      desc: 'Bob generates his own ephemeral key (e), performs ECDH (ee), encrypts his static identity key (s) with ChaCha20-Poly1305, and computes another DH exchange (es).'
    },
    3: {
      title: '3. Alice verifies Bob and Locks Ratchet',
      formula: '-> s, se (Forward Secrecy Verified)',
      desc: 'Alice decrypts and validates Bob\'s identity, transmits her static key (s) encrypted, executes the final DH exchange (se), and locks the symmetric cipher ratchet.'
    }
  };

  stepButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      stepButtons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const step = btn.getAttribute('data-step');
      if (stepData[step]) {
        if (cryptoTitle) cryptoTitle.textContent = stepData[step].title;
        if (cryptoFormula) cryptoFormula.textContent = stepData[step].formula;
        if (cryptoDesc) cryptoDesc.textContent = stepData[step].desc;
      }
    });
  });

  // ==========================================================================
  // 5. Module 3: Opus Audio Waveform Scrubber & Slicing
  // ==========================================================================
  const waveformScrubber = document.getElementById('waveformScrubber');
  const btnPlayVoice = document.getElementById('btnPlayVoice');
  const playIcon = document.getElementById('playIcon');
  const pauseIcon = document.getElementById('pauseIcon');
  const audioTimer = document.getElementById('audioTimer');
  const speedButtons = document.querySelectorAll('.speed-btn');
  const slicesMatrix = document.getElementById('slicesMatrix');
  const sliceDetailCard = document.getElementById('sliceDetailCard');

  let isAudioPlaying = false;
  let audioProgress = 0;
  let audioSpeed = 1.0;
  let audioInterval = null;

  // Generate 36 Waveform Bars
  if (waveformScrubber) {
    waveformScrubber.innerHTML = '';
    const heights = [20, 35, 60, 45, 80, 95, 70, 40, 60, 85, 90, 75, 50, 65, 85, 100, 80, 40, 30, 55, 70, 90, 65, 45, 60, 75, 85, 95, 70, 50, 40, 65, 80, 50, 35, 20];
    heights.forEach((h, idx) => {
      const bar = document.createElement('div');
      bar.className = 'wave-bar';
      bar.style.height = `${h}%`;
      bar.dataset.index = idx;
      bar.addEventListener('click', () => {
        audioProgress = (idx / heights.length);
        updateWaveformUI();
      });
      waveformScrubber.appendChild(bar);
    });
  }

  // Generate 12 Packet Slices
  if (slicesMatrix) {
    slicesMatrix.innerHTML = '';
    for (let i = 1; i <= 12; i++) {
      const slice = document.createElement('div');
      slice.className = i === 1 ? 'slice-item active' : 'slice-item';
      slice.textContent = `Pkt #${i}`;
      slice.dataset.packet = i;
      slice.addEventListener('click', () => {
        document.querySelectorAll('.slice-item').forEach(s => s.classList.remove('active'));
        slice.classList.add('active');
        if (sliceDetailCard) {
          const offsetStart = (i - 1) * 440;
          const offsetEnd = Math.min(i * 440, 5120);
          sliceDetailCard.innerHTML = `
            <strong style="color: var(--text-primary);">Fragment #${i} Selected</strong><br>
            <span style="font-family: var(--font-mono); font-size: 0.76rem; color: var(--text-muted);">
              Seq: ${i - 1} | Offset: ${offsetStart}–${offsetEnd} bytes | Size: 440 B | CRC: 0x${(i * 1337).toString(16).toUpperCase()} | Status: Verified
            </span>
          `;
        }
      });
      slicesMatrix.appendChild(slice);
    }
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
    if (audioTimer) {
      audioTimer.textContent = `00:0${curSec} / 00:07`;
    }
  }

  if (btnPlayVoice) {
    btnPlayVoice.addEventListener('click', () => {
      isAudioPlaying = !isAudioPlaying;
      if (isAudioPlaying) {
        if (playIcon) playIcon.style.display = 'none';
        if (pauseIcon) pauseIcon.style.display = 'block';
        startAudioPlayback();
      } else {
        if (playIcon) playIcon.style.display = 'block';
        if (pauseIcon) pauseIcon.style.display = 'none';
        clearInterval(audioInterval);
      }
    });
  }

  function startAudioPlayback() {
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
        startAudioPlayback();
      }
    });
  });

  // ==========================================================================
  // 6. Module 4: Panic Zeroize Press-and-Hold
  // ==========================================================================
  const btnPanicZeroize = document.getElementById('btnPanicZeroize');
  const memKey1 = document.getElementById('memKey1');
  const memKey2 = document.getElementById('memKey2');
  const memKey3 = document.getElementById('memKey3');
  const memKey4 = document.getElementById('memKey4');

  let panicTimer = null;
  let isZeroized = false;

  if (btnPanicZeroize) {
    const handleStart = (e) => {
      e.preventDefault();
      if (isZeroized) {
        // Reset
        isZeroized = false;
        btnPanicZeroize.style.background = '';
        btnPanicZeroize.innerHTML = '<span>HOLD 1s</span><span style="font-size: 0.65rem; opacity: 0.85;">ZEROIZE</span>';
        if (memKey1) { memKey1.textContent = 'c84f3e91a0...'; memKey1.classList.remove('zeroed'); }
        if (memKey2) { memKey2.textContent = '4b8e2101dd...'; memKey2.classList.remove('zeroed'); }
        if (memKey3) { memKey3.textContent = '14,720 bytes'; memKey3.classList.remove('zeroed'); }
        if (memKey4) { memKey4.textContent = '99e4b100fc...'; memKey4.classList.remove('zeroed'); }
        return;
      }

      btnPanicZeroize.innerHTML = '<span>HOLDING...</span>';
      panicTimer = setTimeout(() => {
        isZeroized = true;
        btnPanicZeroize.style.background = '#10b981';
        btnPanicZeroize.innerHTML = '<span>✓ ZEROED</span><span style="font-size: 0.65rem;">TAP TO RESET</span>';

        // Animate zeroization
        [memKey1, memKey2, memKey3, memKey4].forEach(el => {
          if (el) {
            el.textContent = '0x00000000';
            el.classList.add('zeroed');
          }
        });
      }, 900);
    };

    const handleEnd = () => {
      if (!isZeroized) {
        clearTimeout(panicTimer);
        btnPanicZeroize.innerHTML = '<span>HOLD 1s</span><span style="font-size: 0.65rem; opacity: 0.85;">ZEROIZE</span>';
      }
    };

    btnPanicZeroize.addEventListener('mousedown', handleStart);
    btnPanicZeroize.addEventListener('mouseup', handleEnd);
    btnPanicZeroize.addEventListener('mouseleave', handleEnd);
    btnPanicZeroize.addEventListener('touchstart', handleStart);
    btnPanicZeroize.addEventListener('touchend', handleEnd);
  }

  // ==========================================================================
  // 7. Copy Code Button
  // ==========================================================================
  const copyButtons = document.querySelectorAll('.btn-copy-code');
  copyButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const targetId = btn.getAttribute('data-target');
      const targetEl = document.getElementById(targetId);
      if (targetEl) {
        navigator.clipboard.writeText(targetEl.innerText);
        const originalText = btn.textContent;
        btn.textContent = 'Copied!';
        setTimeout(() => btn.textContent = originalText, 1800);
      }
    });
  });

});
