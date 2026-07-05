import { useEffect, useRef, useState } from 'react';

const API = 'http://localhost:3001';

export function useAgentStoryEvents({ onInteraction, onConnected, onStreamProgress }) {
  const handlersRef = useRef({ onInteraction, onConnected, onStreamProgress });
  handlersRef.current = { onInteraction, onConnected, onStreamProgress };
  const [connected, setConnected] = useState(false);
  const [activeStreams, setActiveStreams] = useState([]);

  useEffect(() => {
    let source = null;
    let retryTimer = null;
    let closed = false;

    const connect = () => {
      source = new EventSource(`${API}/api/events`);

      source.addEventListener('connected', (event) => {
        setConnected(true);
        try {
          const data = JSON.parse(event.data);
          handlersRef.current.onConnected?.(data);
        } catch {
          handlersRef.current.onConnected?.({});
        }
      });

      source.addEventListener('interaction', (event) => {
        try {
          const data = JSON.parse(event.data);
          if (data.capture_key) {
            setActiveStreams(prev => prev.filter(s => s.capture_key !== data.capture_key));
          }
          handlersRef.current.onInteraction?.(data);
        } catch {
          handlersRef.current.onInteraction?.({});
        }
      });

      source.addEventListener('stream-progress', (event) => {
        try {
          const data = JSON.parse(event.data);
          setActiveStreams(prev => {
            const others = prev.filter(s => s.capture_key !== data.capture_key);
            return [...others, data].slice(-5);
          });
          handlersRef.current.onStreamProgress?.(data);
        } catch {
          // ignore malformed stream events
        }
      });

      source.onerror = () => {
        setConnected(false);
        source.close();
        if (!closed) {
          retryTimer = setTimeout(connect, 3000);
        }
      };
    };

    connect();

    return () => {
      closed = true;
      if (retryTimer) clearTimeout(retryTimer);
      if (source) source.close();
      setConnected(false);
      setActiveStreams([]);
    };
  }, []);

  return { connected, activeStreams };
}

export { API };
