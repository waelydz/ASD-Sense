"""Outgoing email: password-reset codes and guardian notifications.

Configure with environment variables before starting the backend:

    ASD_SENSE_SMTP_HOST      e.g. smtp.gmail.com
    ASD_SENSE_SMTP_PORT      default 587 (STARTTLS)
    ASD_SENSE_SMTP_USER
    ASD_SENSE_SMTP_PASSWORD  for Gmail, an "app password"
    ASD_SENSE_SMTP_FROM      default: the user

Without ASD_SENSE_SMTP_HOST nothing is sent: the message is printed in the
backend's terminal instead, so reset codes can still be read during
development.
"""

import os
import smtplib
import threading
from email.message import EmailMessage


def configured() -> bool:
    return bool(os.environ.get("ASD_SENSE_SMTP_HOST"))


def _deliver(to: str, subject: str, body: str) -> None:
    host = os.environ["ASD_SENSE_SMTP_HOST"]
    user = os.environ.get("ASD_SENSE_SMTP_USER", "")
    message = EmailMessage()
    message["From"] = os.environ.get("ASD_SENSE_SMTP_FROM") or user
    message["To"] = to
    message["Subject"] = subject
    message.set_content(body)
    try:
        with smtplib.SMTP(host, int(os.environ.get("ASD_SENSE_SMTP_PORT", "587")), timeout=15) as smtp:
            smtp.starttls()
            if user:
                smtp.login(user, os.environ.get("ASD_SENSE_SMTP_PASSWORD", ""))
            smtp.send_message(message)
    except Exception as e:  # a mail problem must never break the request that caused it
        print(f"WARNING: Could not send email to {to}: {e}")


def send(to: str, subject: str, body: str) -> None:
    """Sends in the background so the API call does not wait on the mail server."""
    if not configured():
        print(f"\n[EMAIL NOT SENT - SMTP is not configured]\nTo: {to}\nSubject: {subject}\n{body}\n")
        return
    threading.Thread(target=_deliver, args=(to, subject, body), daemon=True).start()
