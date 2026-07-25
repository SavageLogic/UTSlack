/*
 * Copyright (c) 2026 Kevin Hasselquist
 * SPDX-License-Identifier: MIT
 *
 * Downloads Slack private media with Authorization: Bearer and caches to disk
 * so QtMultimedia can play file:// URLs (MediaPlayer cannot send auth headers).
 */

#ifndef MEDIACACHE_H
#define MEDIACACHE_H

#include <QObject>
#include <QString>
#include <QHash>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class MediaCache : public QObject
{
    Q_OBJECT

public:
    explicit MediaCache(QObject *parent = nullptr);

    Q_INVOKABLE QString cacheDir() const;
    Q_INVOKABLE bool has(const QString &key) const;
    Q_INVOKABLE QString fileUrlFor(const QString &key) const;
    Q_INVOKABLE bool isDownloading(const QString &key) const;

    // Downloads url with Bearer token into cache/<key>.<ext> (ext without dot).
    // Emits downloadFinished(key, fileUrl) or downloadFailed(key, error).
    Q_INVOKABLE void download(const QString &url,
                              const QString &token,
                              const QString &key,
                              const QString &extension);

signals:
    void downloadFinished(const QString &key, const QString &fileUrl);
    void downloadFailed(const QString &key, const QString &error);

private slots:
    void onReplyFinished();

private:
    QString safeKey(const QString &key) const;
    QString pathFor(const QString &key, const QString &extension) const;

    QNetworkAccessManager m_nam;
    QHash<QString, QNetworkReply *> m_inflight;       // safeKey -> reply
    QHash<QNetworkReply *, QString> m_replySafeKey;
    QHash<QNetworkReply *, QString> m_replyOrigKey;
    QHash<QNetworkReply *, QString> m_replyExt;
};

#endif
