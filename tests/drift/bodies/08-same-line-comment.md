## What changed
Fix the OTP timeout on the sign-in screen.

## How I verified it
- Commands: pnpm test
- iOS: <!-- device or simulator, OS, what you saw --> iPhone 15, iOS 26.6: OTP clears
- Android: <!-- device --> Pixel 8, API 35: same
- Screenshots: ![otp](https://github.com/user-attachments/assets/otp.png)

## Risk
OTP flow only. Not done: no load test yet.

## Checklist
- [x] Tests added or updated
- [x] Docs updated

AI-assisted: no
