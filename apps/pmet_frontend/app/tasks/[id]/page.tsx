'use client';

import { useState, useEffect } from 'react';
import { taskApi } from '@/lib/api';
import { TaskResponse } from '@/lib/types';
import TaskStatusBadge from '@/components/TaskStatusBadge';
import Link from 'next/link';
import { useTranslation } from '@/lib/i18n';
import { TranslationKey } from '@/lib/translations';

interface PageProps {
  params: { id: string };
}

const MODE_KEYS: Record<string, TranslationKey> = {
  promoters_pre: 'mode.promoters_pre',
  promoters: 'mode.promoters',
  intervals: 'mode.intervals',
};

export default function TaskDetailPage({ params }: PageProps) {
  const { id } = params;
  const { t } = useTranslation();
  const [task, setTask] = useState<TaskResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [polling, setPolling] = useState(false);

  useEffect(() => {
    fetchTask();

    return () => {
      setPolling(false);
    };
  }, [id]);

  useEffect(() => {
    if (task && (task.status === 'pending' || task.status === 'running')) {
      setPolling(true);
      const interval = setInterval(fetchTask, 5000);
      return () => {
        clearInterval(interval);
        setPolling(false);
      };
    }
  }, [task?.status]);

  const fetchTask = async () => {
    try {
      const response = await taskApi.get(id);
      setTask(response);
    } catch (error) {
      console.error('Failed to fetch task:', error);
    } finally {
      setLoading(false);
    }
  };

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    return date.toLocaleString();
  };

  if (loading) {
    return (
      <div className="max-w-5xl mx-auto text-center py-12">
        {t('task.loading')}
      </div>
    );
  }

  if (!task) {
    return (
      <div className="max-w-5xl mx-auto text-center py-12">
        <p className="text-slate-500">{t('task.not_found')}</p>
        <Link href="/tasks" className="text-primary-700 hover:underline mt-4 inline-block">
          {t('task.back')}
        </Link>
      </div>
    );
  }

  return (
    <div className="max-w-5xl mx-auto">
      <div className="flex items-center gap-2 mb-6">
        <Link href="/tasks" className="text-slate-500 hover:text-slate-700">
          {t('task.back')}
        </Link>
      </div>

      <div className="card">
        <div className="flex justify-between items-start mb-6">
          <div>
            <h1 className="text-2xl font-bold">{task.task_id}</h1>
            <p className="text-slate-500">{t(MODE_KEYS[task.mode])}</p>
          </div>
          <TaskStatusBadge status={task.status} />
        </div>

        {polling && (
          <div className="mb-6 p-4 bg-blue-50 rounded-lg text-blue-700">
            <div className="flex items-center gap-2">
              <div className="animate-spin h-4 w-4 border-2 border-blue-500 border-t-transparent rounded-full" />
              {t('task.running_msg')}
            </div>
          </div>
        )}

        <div className="grid md:grid-cols-2 gap-6">
          <div>
            <h3 className="font-medium text-slate-500 mb-1">{t('task.email')}</h3>
            <p>{task.email}</p>
          </div>

          <div>
            <h3 className="font-medium text-slate-500 mb-1">{t('task.created')}</h3>
            <p>{formatDate(task.created_at)}</p>
          </div>

          {task.started_at && (
            <div>
              <h3 className="font-medium text-slate-500 mb-1">{t('task.started')}</h3>
              <p>{formatDate(task.started_at)}</p>
            </div>
          )}

          {task.completed_at && (
            <div>
              <h3 className="font-medium text-slate-500 mb-1">{t('task.completed')}</h3>
              <p>{formatDate(task.completed_at)}</p>
            </div>
          )}
        </div>

        {task.error_message && (
          <div className="mt-6 p-4 bg-red-50 rounded-lg">
            <h3 className="font-medium text-red-700 mb-1">{t('task.error')}</h3>
            <p className="text-red-600">{task.error_message}</p>
          </div>
        )}

        {task.status === 'completed' && (
          <div className="mt-6">
            <a
              href={taskApi.downloadResult(task.task_id)}
              className="btn-primary inline-block"
            >
              {t('task.download')}
            </a>
            <Link
              href={`/tasks/${task.task_id}/visualize`}
              className="btn-secondary inline-block ml-4"
            >
              {t('task.visualize')}
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}
