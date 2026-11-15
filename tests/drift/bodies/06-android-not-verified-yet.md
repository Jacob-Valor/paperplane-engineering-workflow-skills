## What changed
Fix the OTP timeout on the sign-in screen.

## How I verified it
- Commands: pnpm test
- iOS: iPhone 15 simulator, iOS 26.6: OTP screen clears after 30s
- Android: not verified yet
- Screenshots: ![otp](https://github.com/user-attachments/assets/otp.png)

## Risk
OTP flow only. Not done: no load test yet.

## Checklist
- [x] Tests added or updated
- [x] Docs updated

AI-assisted: no
