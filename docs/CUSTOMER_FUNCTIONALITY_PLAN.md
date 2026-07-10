# Customer Functionality Plan

## Goal

Implement customer-side functionality step by step, bringing each flow to a production-ready level before moving to the next one.

## Principles

1. Work on one customer functionality at a time.
2. Finish the full user flow, not only the screen visuals.
3. Verify UI states, API integration, validation, navigation, and empty/error/loading states.
4. Keep the customer experience simple, fast, and trustworthy.

## Full Customer Functionality List

### Auth And Session

1. Onboarding
2. Login by phone number
3. SMS code verification
4. Customer role selection
5. Logout
6. Session persistence

### Customer Home

7. City display and city selection
8. Search by service/task
9. Category browsing
10. View all categories
11. Best masters section
12. Open master profile
13. Active orders section
14. Quick jump to chats
15. Quick jump to profile or chats in MVP

### Create Order

16. Start order creation
17. Choose category
18. Write task description
19. Use quick templates
20. Choose district
21. Enter address
22. Choose execution time
23. Set budget
24. Review order before publish
25. Publish order

### Customer Orders

26. View list of own orders
27. Open order details
28. See order status
29. See views/responses count
30. Refresh order data
31. Empty states for orders

### Responses And Master Selection

32. View responses from masters
33. Compare response price and text
34. Open master profile from response
35. Open chat from response
36. Choose master for an order

### Masters Directory

37. Browse masters
38. Filter/search masters
39. View master profile
40. View skills
41. View portfolio
42. View rating/reviews

### Chat

43. View chat list
44. Open chat
45. Send message
46. Correct role-based message rendering
47. Empty chat state

### Wallet

48. Deferred for customer MVP
49. Customer usage is free at launch
50. Payment flow remains on master side
51. Revisit after core customer/master flows are stable

### Profile

52. View customer profile
53. Edit name
54. Edit city
55. Edit district
56. Save profile changes

### Cross-Cutting Product Quality

57. Loading states
58. Error states
59. Validation states
60. Pull-to-refresh where relevant
61. Consistent empty states
62. Navigation consistency

## Implementation Order

1. Create order flow
2. Customer orders list
3. Order detail and responses
4. Chat with master
5. Master profile from customer side
6. Customer home utilities
7. Wallet
8. Customer profile

## Current Focus

### 1. Create Order Flow

Status: completed

What is done:

- category selection works
- validation blocks incomplete steps
- publish request sends correct payload
- created order opens immediately after publish
- review screen shows derived title and clean placeholders

### 2. Customer Orders List

Status: completed

What is done:

- order cards show status, budget, created time, views, and responses
- orders summary is visible above the list
- newly created orders are easier to find and open
- detail screen uses the same status logic as the list

### 3. Order Detail And Responses

Status: completed

What is done:

- response cards have working actions
- customer can open master profile from response
- customer can choose a master from response
- chosen master becomes visible in order details
- chat is created and opened through the selection flow

### 4. Chat With Master

Status: in progress

Target: make customer chat feel reliable, clear, and comfortable for real coordination with the selected master.

What this includes:

- clear chat list naming
- open chat with human context, not only order title
- better loading, error, and empty states
- safe message sending flow
- stronger order context inside the conversation

Definition of done:

- the customer immediately understands who the chat is with
- sending messages feels stable and obvious
- chat states are understandable even when the dialog is empty or loading
- the order context stays visible during the conversation
