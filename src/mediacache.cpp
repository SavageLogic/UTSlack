/*
 * Copyright (c) 2026 Kevin Hasselquist
 * SPDX-License-Identifier: MIT
 */

#include "mediacache.h"

#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QNetworkRequest>
#include <QUrl>
#include <QDebug>
#include <QRegularExpression>

MediaCache::MediaCache(QObject *parent)
    : QObject(parent)
{
    QDir().mkpath(cacheDir());
}

QString MediaCache::cacheDir() const
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QString path = base;
    if (!path.endsWith(QLatin1Char('/')))
        path += QLatin1Char('/');
    path += QStringLiteral("media/");
    return path;
}

QString MediaCache::safeKey(const QString &key) const
{
    QString k = key;
    k.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9._-]")), QStringLiteral("_"));
    if (k.isEmpty())
        k = QStringLiteral("file");
    return k;
}

QString MediaCache::pathFor(const QString &key, const QString &extension) const
{
    QString ext = extension;
    if (ext.startsWith(QLatin1Char('.')))
        ext = ext.mid(1);
    if (ext.isEmpty())
        ext = QStringLiteral("bin");
    return cacheDir() + safeKey(key) + QLatin1Char('.') + ext;
}

bool MediaCache::has(const QString &key) const
{
    const QDir dir(cacheDir());
    const QStringList matches = dir.entryList(QStringList() << (safeKey(key) + QStringLiteral(".*")),
                                              QDir::Files);
    for (const QString &name : matches) {
        QFile f(cacheDir() + name);
        if (f.exists() && f.size() > 0)
            return true;
    }
    return false;
}

QString MediaCache::fileUrlFor(const QString &key) const
{
    const QDir dir(cacheDir());
    const QStringList matches = dir.entryList(QStringList() << (safeKey(key) + QStringLiteral(".*")),
                                              QDir::Files);
    for (const QString &name : matches) {
        const QString path = cacheDir() + name;
        QFile f(path);
        if (f.exists() && f.size() > 0)
            return QUrl::fromLocalFile(path).toString();
    }
    return QString();
}

bool MediaCache::isDownloading(const QString &key) const
{
    return m_inflight.contains(safeKey(key));
}

void MediaCache::download(const QString &url,
                          const QString &token,
                          const QString &key,
                          const QString &extension)
{
    const QString sk = safeKey(key);
    if (sk.isEmpty() || url.isEmpty()) {
        emit downloadFailed(key, QStringLiteral("missing url/key"));
        return;
    }

    const QString existing = fileUrlFor(key);
    if (!existing.isEmpty()) {
        emit downloadFinished(key, existing);
        return;
    }

    if (m_inflight.contains(sk))
        return;

    QNetworkRequest req{QUrl(url)};
#if QT_VERSION >= QT_VERSION_CHECK(5, 9, 0)
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
#else
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
#endif
    req.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("*/*"));
    if (!token.isEmpty())
        req.setRawHeader(QByteArrayLiteral("Authorization"),
                         QByteArrayLiteral("Bearer ") + token.toUtf8());

    QNetworkReply *reply = m_nam.get(req);
    m_inflight.insert(sk, reply);
    m_replySafeKey.insert(reply, sk);
    m_replyOrigKey.insert(reply, key);
    m_replyExt.insert(reply, extension);
    connect(reply, &QNetworkReply::finished, this, &MediaCache::onReplyFinished);
    qDebug() << "[MediaCache] download start" << sk << url;
}

void MediaCache::onReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply)
        return;

    const QString sk = m_replySafeKey.take(reply);
    const QString origKey = m_replyOrigKey.take(reply);
    const QString ext = m_replyExt.take(reply);
    m_inflight.remove(sk);
    reply->deleteLater();

    if (origKey.isEmpty())
        return;

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[MediaCache] download error" << origKey << reply->errorString();
        emit downloadFailed(origKey, reply->errorString());
        return;
    }

    // Peek first bytes before committing whole body to detect Slack HTML login pages
    const QByteArray peek = reply->peek(64).trimmed().toLower();
    if (peek.startsWith("<!doctype") || peek.startsWith("<html")) {
        qWarning() << "[MediaCache] got HTML instead of media (auth failed?)" << origKey;
        emit downloadFailed(origKey, QStringLiteral("authentication failed"));
        return;
    }

    QDir().mkpath(cacheDir());
    const QString path = pathFor(origKey, ext);
    const QString tmpPath = path + QStringLiteral(".part");
    QFile out(tmpPath);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        emit downloadFailed(origKey, QStringLiteral("cannot write cache"));
        return;
    }

    qint64 total = 0;
    while (!reply->atEnd()) {
        const QByteArray chunk = reply->read(256 * 1024);
        if (chunk.isEmpty())
            break;
        if (out.write(chunk) != chunk.size()) {
            out.close();
            out.remove();
            emit downloadFailed(origKey, QStringLiteral("short write"));
            return;
        }
        total += chunk.size();
    }
    out.close();

    if (total <= 0) {
        QFile::remove(tmpPath);
        emit downloadFailed(origKey, QStringLiteral("empty body"));
        return;
    }

    QFile::remove(path);
    if (!QFile::rename(tmpPath, path)) {
        QFile::remove(tmpPath);
        emit downloadFailed(origKey, QStringLiteral("cannot finalize cache"));
        return;
    }

    const QString fileUrl = QUrl::fromLocalFile(path).toString();
    qDebug() << "[MediaCache] cached" << origKey << "bytes=" << total << fileUrl;
    emit downloadFinished(origKey, fileUrl);
}
