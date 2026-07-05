import { useState, useEffect, useCallback } from 'react';
import { API } from './useAgentStoryEvents';
import { sortProjectsByRecentActivity } from '../utils/interactionUtils';

export function useProjects(refreshToken = 0) {
  const [projects, setProjects] = useState([]);

  const fetchProjects = useCallback(async () => {
    try {
      const res = await fetch(`${API}/api/projects`);
      if (res.ok) {
        const data = await res.json();
        setProjects(sortProjectsByRecentActivity(data));
      }
    } catch (err) {
      console.error('Project list refresh failed:', err);
    }
  }, []);

  useEffect(() => {
    fetchProjects();
  }, [fetchProjects, refreshToken]);

  return projects;
}
