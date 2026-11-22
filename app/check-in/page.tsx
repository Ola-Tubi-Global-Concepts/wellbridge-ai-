"use client";

import { useState } from "react";

type SafetyChoice = "safe" | "unsure" | "unsafe";

export default function CheckInPage() {
  const [choice, setChoice] = useState("");
  const [shown, setShown] = useState(false);
  const [safetyChoice, setSafetyChoice] = useState<SafetyChoice | "">("");
  const [safetySkipped, setSafetySkipped] = useState(false);

  const wellbeingGuidance =
    choice === "good"
      ? "Keep up routines and connections that support your wellbeing. Consider checking in with someone you trust."
      : "You may find it helpful to speak with someone you trust or a qualified health professional.";

  function handleFeelingChange(value: string) {
    setChoice(value);
    setShown(false);
    setSafetyChoice("");
    setSafetySkipped(false);
  }

  return (
    <div className="container content">
      <div className="page-title">
        <p className="eyebrow">WELLBEING REFLECTION</p>
        <h1>How have things been for you?</h1>
        <p>
          This optional reflection is for general self-awareness only. It is
          not a validated screening tool, diagnosis or treatment recommendation.
        </p>
      </div>

      <section className="panel">
        <label htmlFor="feeling">
          <strong>How would you describe your wellbeing today?</strong>
        </label>
        <select
          id="feeling"
          className="field"
          value={choice}
          onChange={(event) => handleFeelingChange(event.target.value)}
        >
          <option value="">Choose a response</option>
          <option value="good">Generally okay</option>
          <option value="mixed">Up and down</option>
          <option value="difficult">Finding things difficult</option>
          <option value="overwhelmed">Feeling overwhelmed</option>
        </select>

        <button
          className="button"
          disabled={!choice}
          onClick={() => {
            setShown(true);
            setSafetyChoice("");
            setSafetySkipped(false);
          }}
        >
          View general guidance
        </button>

        {shown && (
          <div className="notice" role="status" aria-live="polite">
            <strong>One more optional safety check</strong>
            <p>
              Are you feeling safe right now? This question does not assess or
              diagnose risk. Your answer stays in this page session and is not
              sent to a server or saved by this prototype.
            </p>

            <fieldset>
              <legend>Choose the response that best describes how you feel.</legend>
              <label>
                <input
                  type="radio"
                  name="safety"
                  value="safe"
                  checked={safetyChoice === "safe"}
                  onChange={() => setSafetyChoice("safe")}
                />{" "}
                Yes, I feel safe.
              </label>
              <br />
              <label>
                <input
                  type="radio"
                  name="safety"
                  value="unsure"
                  checked={safetyChoice === "unsure"}
                  onChange={() => setSafetyChoice("unsure")}
                />{" "}
                I&apos;m not sure.
              </label>
              <br />
              <label>
                <input
                  type="radio"
                  name="safety"
                  value="unsafe"
                  checked={safetyChoice === "unsafe"}
                  onChange={() => setSafetyChoice("unsafe")}
                />{" "}
                No, I don&apos;t feel safe.
              </label>
            </fieldset>

            <button
              type="button"
              className="button secondary"
              onClick={() => {
                setSafetySkipped(true);
                setSafetyChoice("");
              }}
            >
              Skip this question and view general guidance
            </button>

            {safetySkipped && (
              <div className="notice" role="status">
                <strong>General supportive guidance</strong>
                <p>{wellbeingGuidance}</p>
                <p>
                  If you feel unsafe or may harm yourself or someone else,
                  seek immediate in-person help from local emergency services
                  or the nearest hospital. WellBridge AI is not monitored and
                  cannot contact anyone or arrange help.
                </p>
              </div>
            )}

            {safetyChoice === "safe" && (
              <div className="notice" role="status">
                <strong>Consider a supportive next step</strong>
                <p>{wellbeingGuidance}</p>
                <p>
                  If your safety situation changes or you become worried you
                  may harm yourself or someone else, seek immediate in-person
                  help from local emergency services or the nearest hospital.
                </p>
              </div>
            )}

            {safetyChoice === "unsure" && (
              <div className="notice" role="alert">
                <strong>Please connect with someone who can support you.</strong>
                <p>
                  Consider contacting someone you trust and a qualified health
                  professional now. If possible, ask someone you trust to stay
                  with you while you seek support. If you may harm yourself or
                  someone else, or cannot stay safe, seek immediate in-person
                  help from local emergency services or the nearest hospital.
                </p>
                <p>
                  WellBridge AI is not monitored and cannot contact anyone or
                  arrange help for you.
                </p>
              </div>
            )}

            {safetyChoice === "unsafe" && (
              <div className="notice" role="alert">
                <strong>Seek immediate in-person help now.</strong>
                <p>
                  Contact local emergency services or go to the nearest
                  hospital emergency department. If possible, tell someone you
                  trust and ask them to stay with you while you get help.
                </p>
                <p>
                  Do not rely on WellBridge AI in an emergency. This prototype
                  is not monitored and cannot contact responders, clinicians
                  or family members.
                </p>
              </div>
            )}
          </div>
        )}
      </section>

      <p>
        <strong>Privacy:</strong> Your wellbeing and safety selections are held
        only in this page session. They are not sent to a server or saved by
        this prototype.
      </p>
      <p>
        If you are in immediate danger, do not rely on this website. Contact
        local emergency services or go to the nearest emergency department.
      </p>
    </div>
  );
}
