# Spazio — Room Designer & Furniture Visualizer

> **PUSL3122 HCI, Computer Graphics and Visualisation — Coursework 2025/26**  
> University of Plymouth · Group Assignment · Term 2  
> Submission Deadline: 19th March 2026

---

## Table of Contents

- [Overview](#overview)
- [Screenshots](#screenshots)
- [Features](#features)
- [Technology Stack](#technology-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [User Accounts](#user-accounts)
- [How to Use](#how-to-use)
- [3D Assets & Credits](#3d-assets--credits)
- [Dependencies](#dependencies)
- [GitHub & Video Links](#github--video-links)

---

## Overview

**Spazio** is a desktop furniture visualisation application built with Flutter for Windows. It allows furniture store designers (admins) to create virtual room layouts for customers, and allows customers (users) to view, interact with, and purchase designs.

The application supports full **2D canvas layout editing** and **realistic 3D rendering** powered by Three.js, running inside a WebView2 embedded browser. It was developed to meet the requirements of the PUSL3122 coursework brief — a room visualisation tool for a furniture retailer.

---

## Screenshots

### Authentication

| Login & Sign In | Create Account | Reset Password |
|---|---|---|
| ![Login](screenshots/Login_Signup.png) | ![Create Account](screenshots/Create_Account.png) | ![Reset Password](screenshots/Reset_Password.png) |

---

### Dashboard

| Main Dashboard | Notifications Panel |
|---|---|
| ![Dashboard](screenshots/Dashboard.png) | ![Notifications](screenshots/Notifications.png) |

| My Projects | New Design Dialog |
|---|---|
| ![My Projects](screenshots/My_Projects.png) | ![New Design](screenshots/When_making_a_new_project_Design.png) |

| Templates | Settings |
|---|---|
| ![Templates](screenshots/Templates.png) | ![Settings](screenshots/Settings.png) |

| Help & Shortcuts | Pricing Manager |
|---|---|
| ![Help](screenshots/Help_Shortcuts.png) | ![Pricing](screenshots/Pricing.png) |

---

### 2D Canvas Editor

| 2D Editor — Furniture Sidebar | 2D Editor — Scrolled (Room Shape & 3D Controls) |
|---|---|
| ![2D Editor](screenshots/2D_editor.png) | ![2D Editor Scrolled](screenshots/2D_editor_Scrolled_side_bar.png) |

| Colour Scheme Picker | Canvas Background Colour |
|---|---|
| ![Colour Scheme](screenshots/Colour_Scheme_Picker.png) | ![Canvas Background](screenshots/Canvas_Background_Colour_Change.png) |

| Furniture Canvas + Ceiling Canvas (Split View) |
|---|
| ![Ceiling Canvas](screenshots/Furniture_canvas_Ceiling_Canvas.png) |

---

### Realistic 3D View

| 3D View | Shading & Lighting Panel |
|---|---|
| ![3D View](screenshots/Realistic_3D_View.png) | ![Shading](screenshots/Shading_Lightning_Options.png) |

| 3D Background Colour Picker | Furniture Size & Tint Control |
|---|---|
| ![3D Background](screenshots/3D_View_s_Background_colour_picker.png) | ![Size and Tint](screenshots/Change_furniture_size_and_tint.png) |

---

### Billing & Checkout

| My Bill (Itemised) | Checkout — Delivery Details |
|---|---|
| ![My Bill](screenshots/View_bill_My_Bill.png) | ![Delivery](screenshots/Checkout_Delivery_details.png) |

| Checkout — Payment | Order Confirmation |
|---|---|
| ![Payment](screenshots/Checkout_Payment.png) | ![Order Placed](screenshots/Order_Placed.png) |

---

## Features

### Two User Roles

| Feature | Admin (Designer) | User (Customer) |
|---|---|---|
| Login / Register | ✅ | ✅ |
| Create new designs | ✅ | ❌ |
| Edit room size & shape | ✅ | ❌ |
| Place & move furniture | ✅ | ✅ |
| Rotate furniture | ✅ | ✅ |
| Undo / Redo | ✅ | ✅ |
| 3D View | ✅ | ✅ |
| View Bill & Purchase | ✅ | ✅ |
| Set furniture prices | ✅ | ❌ |
| Share designs with users | ✅ | ❌ |
| Request a design | ❌ | ✅ |
| Delete own designs | ✅ | ✅ |

### 2D Canvas Editor
- Place, move, rotate and delete furniture on a 2D floor plan
- 30+ room shapes (rectangle, circle, hexagon, octagon, star, heart, cross, asteroid, and more)
- Snap-to-grid for precise placement
- Ceiling layer for overhead lighting (split-screen Furniture Canvas + Ceiling Canvas)
- Multi-select with marquee drag or Ctrl+click
- Colour scheme picker with 8 presets and live preview (walls, floor, ceiling, trim, accent)
- Canvas background colour picker with hex input
- Room size sliders (width, depth, wall height)
- Zoom controls and pan mode (Hand tool)
- Undo / Redo

### Realistic 3D View
- Three.js r128-powered real-time 3D rendering via embedded WebView2
- Full 360° orbit (left-drag), zoom (scroll/W/S), and pan (right-drag/arrows)
- Select mode with blue bounding box highlight on selected furniture
- Furniture size scaling with global save (shared across all users and projects)
- Per-furniture colour tinting: colour picker, intensity slider, Save Tint
- Apply tint to ALL furniture with one button
- Shading & Lighting panel: Ambient, Sunlight, Fill light, Sky light sliders
- 6 lighting presets: Natural, Bright, Moody, Dramatic, Night, Showroom
- Per-item brightness and darkness controls
- Wall height control
- Background colour picker with presets and custom hex input
- Room dimensions displayed bottom-right

### Lighting System
- 5 light types: Floor Lamp, Table Lamp, Wall Light, Ceiling Spot, Window Light
- Real Three.js light sources (PointLight, SpotLight, DirectionalLight)
- Table lamps auto-snap to the surface of furniture beneath them
- Wall lights and windows auto-snap to the nearest wall
- Ceiling spots placed via the dedicated Ceiling Canvas layer

### Pricing & Checkout
- Admin-only Pricing Manager: set a price per furniture type or custom GLB
- Currency selector (£, $, €, Rs) — saved globally
- Prices saved globally — visible to all users across all projects
- "View Bill" button in both 2D toolbar and 3D view
- Itemised bill: item, quantity, unit price, line total, subtotal, VAT (20%), grand total
- 2-step checkout: Delivery Details → Payment → Order Confirmation
- Payment methods: Card (encrypted), PayPal, Bank Transfer
- Order confirmation with unique order number

### Project Management
- Create, rename, duplicate, delete, and favourite projects
- Share designs with specific registered user accounts
- Design request workflow: user submits → admin fulfils → design auto-shared back
- Project search and sort (most recent / name A–Z / most furniture)
- 10+ pre-configured room templates grouped by room type
- Notification panel with app tips and updates
- Help & Shortcuts dialog covering all keyboard and mouse controls

### Custom Furniture
- Import any `.glb` 3D model file as custom furniture
- Auto-measures natural bounding box for accurate 2D footprint
- Custom furniture appears in sidebar with thumbnails
- Compatible with the Pricing Manager and bill system

---

## Technology Stack

| Layer | Technology |
|---|---|
| UI Framework | Flutter (Dart) — Windows desktop |
| 3D Rendering | Three.js r128 (via WebView2 embedded browser) |
| 3D Model Format | GLTF / GLB |
| Local HTTP Server | Dart `shelf` package (serves 3D assets) |
| Persistence | `shared_preferences` (local device storage) |
| File Import | `file_picker` package |
| WebView | `webview_windows` package |
| State Management | Flutter `setState` + `ValueNotifier` |

---

## Project Structure

```
lib/
├── main.dart                        # App entry point, service initialisation
├── screens/
│   ├── login_screen.dart            # Login / register / password reset
│   ├── dashboard_screen.dart        # Main dashboard, nav, project management
│   ├── editor_2d_screen.dart        # 2D room canvas editor
│   ├── realistic_3d_screen.dart     # 3D viewer wrapper (Flutter side)
│   ├── pricing_manager_screen.dart  # Admin: set prices per furniture type
│   ├── bill_preview_screen.dart     # Itemised bill from current design
│   └── payment_screen.dart         # Checkout: delivery + payment + confirmation
├── models/
│   ├── furniture_model.dart         # FurnitureModel, FurnitureType enum
│   ├── room_shape.dart              # RoomShape enum + 30+ shape definitions
│   └── design_project.dart         # PersistedProject, RoomTemplate, RoomType
├── services/
│   ├── layout_persistence_service.dart  # Save/load layouts and projects
│   ├── furniture_scale_service.dart     # Global furniture size persistence
│   ├── pricing_service.dart             # Global furniture price persistence
│   ├── custom_furniture_registry.dart   # Custom GLB import & registry
│   ├── asset_server.dart                # Local HTTP server for 3D assets
│   └── thumbnail_cache.dart             # Top-down 3D thumbnail cache
├── widgets/
│   ├── room_canvas.dart             # 2D canvas: placement, drag, rotate
│   ├── mouse_tool_sidebar.dart      # Select / Hand / Draw tool switcher
│   └── colour_scheme_picker.dart   # Colour scheme picker widget
└── theme/
    └── app_theme.dart               # Colours, typography, theme data

assets/
├── room_viewer.html                 # Three.js 3D scene (entire renderer)
├── three.min.js                     # Three.js r128
├── OrbitControls.js                 # Camera orbit controls
├── GLTFLoader.js                    # GLTF/GLB model loader
└── models/                          # 25 built-in GLB furniture models

screenshots/                         # All 24 application screenshots
```

---

## Getting Started

### Prerequisites
- Flutter SDK (≥ 3.0)
- Windows 10/11 with **WebView2 Runtime** installed
- Visual Studio 2022 with Desktop C++ workload

### Installation

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/spazio-room-designer.git
cd spazio-room-designer

# Install dependencies
flutter pub get

# Run on Windows desktop
flutter run -d windows
```

### Build Release

```bash
flutter build windows --release
```

---

## User Accounts

All data is stored locally on the device. No internet connection required.

### Default Admin Account
| Field | Value |
|---|---|
| Email | `admin@gmail.com` |
| Password | `admin123` |

### Creating a User Account
1. Open the app → click **"Create one"** on the login screen
2. Enter any email and password → click **Create Account**
3. Log back in with those credentials

---

## How to Use

### As Admin (Designer)
1. Log in with `admin@gmail.com` / `admin123`
2. Click **+ New Design** → name your project → editor opens
3. Select furniture from the left panel → click canvas to place
4. Drag items to move · drag the blue handle to rotate
5. Open **Realistic 3D View** to see the room rendered in 3D
6. In 3D: enable **Select ON** → click furniture → adjust Scale, Tint, Shading
7. Go to **Pricing** in the sidebar to set prices for each furniture type
8. Share designs with users via the project card three-dot menu

### As User (Customer)
1. Register and log in
2. Click **Request Design** to ask the admin to design a room for you
3. Once shared, the design appears under **Shared with Me**
4. Open the design → explore in 2D and 3D
5. Click the **View Bill** button (receipt icon) to see an itemised price list
6. Click **Proceed to Purchase** → fill in delivery and payment details

---

## 3D Assets & Credits

| Asset | Source | Licence |
|---|---|---|
| Three.js r128 | [threejs.org](https://threejs.org) | MIT |
| OrbitControls.js | Three.js examples | MIT |
| GLTFLoader.js | Three.js examples | MIT |
| Furniture GLB models | [Sketchfab](https://sketchfab.com) / [Poly Pizza](https://polypizza.io) | CC Attribution |
| App icons | Flutter Material Icons | Apache 2.0 |

> All 3D models are licensed for free use with attribution. See individual model pages for full licence details.

---

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  webview_windows: ^0.4.0
  shared_preferences: ^2.2.0
  file_picker: ^6.0.0
  shelf: ^1.4.0
  shelf_static: ^1.1.0
  path: ^1.9.0
```

---

## GitHub & Video Links

| Resource | Link |
|---|---|
| GitHub Repository | `https://github.com/YOUR_USERNAME/spazio-room-designer` |
| YouTube Demo Video | `https://youtu.be/YOUR_VIDEO_ID` |


---

## Module Information

| | |
|---|---|
| **Module** | PUSL3122 — HCI, Computer Graphics and Visualisation |
| **Module Leader** | Dr Taimur Bakhshi |
| **Submission Deadline** | 19th March 2026 |
| **Assessment Type** | Group Coursework (50% of module) |
| **University** | University of Plymouth |
