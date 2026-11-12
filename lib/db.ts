// Database access intentionally remains unimplemented in this prototype.
// Do not persist health or wellbeing data until authentication, consent,
// retention, security and clinical governance have been approved.
export function databaseNotConfigured():never{throw new Error("Database persistence is not enabled in this prototype.");}
