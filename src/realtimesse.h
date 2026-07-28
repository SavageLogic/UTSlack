/*
 * Copyright (c) 2026 Kevin Hasselquist
 * SPDX-License-Identifier: MIT
 *
 * Outbound Server-Sent Events client for relay fan-out.
 */

#ifndef REALTIMESSE_H
#define REALTIMESSE_H

#include <QObject>
#include <QString>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class RealtimeSse : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit RealtimeSse(QObject *parent = nullptr);
    ~RealtimeSse() override;

    QString url() const { return m_url; }
    void setUrl(const QString &url);

    bool active() const { return m_active; }
    QString status() const { return m_status; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void open();
    Q_INVOKABLE void close();

signals:
    void urlChanged();
    void activeChanged();
    void statusChanged();
    void lastErrorChanged();
    // One complete SSE data payload (JSON string or raw data field).
    void eventReceived(const QString &data);

private slots:
    void onReadyRead();
    void onFinished();
    void onError(QNetworkReply::NetworkError code);

private:
    void setStatus(const QString &status);
    void setActive(bool active);
    void setLastError(const QString &error);
    void consumeBuffer();
    void abortReply();

    QNetworkAccessManager m_nam;
    QNetworkReply *m_reply;
    QString m_url;
    QString m_buffer;
    QString m_dataLines;
    bool m_active;
    QString m_status;
    QString m_lastError;
};

#endif
