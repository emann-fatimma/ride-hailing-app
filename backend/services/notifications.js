const twilio = require('twilio');
const nodemailer = require('nodemailer');

const smsConfigured = Boolean(
  process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_PHONE_NUMBER
);
const emailConfigured = Boolean(process.env.GMAIL_USER && process.env.GMAIL_APP_PASSWORD);

const twilioClient = smsConfigured
  ? twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN)
  : null;

const mailTransporter = emailConfigured
  ? nodemailer.createTransport({
      service: 'gmail',
      auth: { user: process.env.GMAIL_USER, pass: process.env.GMAIL_APP_PASSWORD }
    })
  : null;

async function sendSms(to, body) {
  if (!twilioClient) throw new Error('SMS provider is not configured');
  await twilioClient.messages.create({ to, body, from: process.env.TWILIO_PHONE_NUMBER });
}

async function sendEmail(to, subject, text) {
  if (!mailTransporter) throw new Error('Email provider is not configured');
  await mailTransporter.sendMail({ from: process.env.GMAIL_USER, to, subject, text });
}

module.exports = { smsConfigured, emailConfigured, sendSms, sendEmail };
