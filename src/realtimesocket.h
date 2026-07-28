/*
 * Copyright (c) 2026 Kevin Hasselquist
 * SPDX-License-Identifier: MIT
 *
 * Thin QWebSocket wrapper for Slack Socket Mode (and similar) from QML.
 */

#ifndef REALTIMESOCKET_H
#define REALTIMESOCKET_H

#include <QObject>
#include <QString>
#include <QWebSocket>

class RealtimeSocket : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit RealtimeSocket(QObject *parent = nullptr);

    QString url() const { return m_url; }
    void setUrl(const QString &url);

    bool active() const { return m_active; }
    QString status() const { return m_status; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void open();
    Q_INVOKABLE void close();
    Q_INVOKABLE void sendText(const QString &text);

signals:
    void urlChanged();
    void activeChanged();
    void statusChanged();
    void lastErrorChanged();
    void textReceived(const QString &text);

private slots:
    void onConnected();
    void onDisconnected();
    void onTextMessageReceived(const QString &message);
    void onError(QAbstractSocket::SocketError error);

private:
    void setStatus(const QString &status);
    void setActive(bool active);
    void setLastError(const QString &error);

    QWebSocket m_socket;
    QString m_url;
    bool m_active;
    QString m_status;
    QString m_lastError;
};

#endif
