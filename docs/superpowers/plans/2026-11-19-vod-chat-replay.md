# VOD Chat Replay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Twitch VOD chat replay in Stitch Revitalized for Roku so chat comments sync with video playback during recorded broadcasts.

**Architecture:** 
A dedicated SceneGraph Task node (`VodChatJob`) queries Twitch's GraphQL endpoint (`https://gql.twitch.tv/gql`) for video comments paginated by offset and cursor. The `VideoPlayer` scene passes the VOD `contentId` and playback position to the `Chat` component, which drives `VodChatJob`. When video playback advances, comments whose `contentOffsetSeconds` match the current timestamp are queued into `Chat.brs` and rendered through the existing chat and emote pipeline; timeline seeks flush the buffer and re-anchor the GraphQL offset.

**Tech Stack:** Roku SceneGraph, BrightScript, Twitch GraphQL API, BrighterScript compiler (`bsc`).

**Spec:** In-repo architectural analysis of `Chat.brs`, `ChatJob.brs`, `VideoPlayer.brs`, and Twitch GraphQL `video(id).comments` schema.

## Global Constraints

- Must run smoothly on Roku OS 11+ and resource-constrained Roku devices (Roku Express 4K+ with 1GB RAM).
- No unhandled exceptions on missing chat or disabled chat (`isChatEnabled()`).
- All network operations must occur inside SceneGraph `Task` threads (never on the render thread).
- Emote rendering must reuse the existing `m.global.emoteCache` and `EmoteJob` pipeline.
- Maintain compatibility with live IRC chat when playing live streams (`isLiveContent`).

## Review Focus

1. **Timeline scrubbing / seek:** Fast-forwarding or rewinding must cancel pending queue timers, flush buffered messages, and request a new GraphQL chunk at the new `video.position`.
2. **Empty or sub-only VOD chat:** Videos with chat disabled, subscriber-only archives, or zero comments must fail gracefully without crash or UI lockup.
3. **Memory pressure:** Do not buffer more than 60 seconds of chat ahead of current playback position to prevent out-of-memory crashes on Roku.
4. **Playback pause/resume:** Pausing video must pause chat message dispatch; resuming must resume dispatch without skipping or message bursts.
5. **Clean player exit:** Leaving the player must terminate `VodChatJob` and unobserve all fields immediately.

---

### Task 1: Create GraphQL Query & `VodChatJob` Component

**Files:**
- Create: `source/graphql/VideoComments_Query.gql`
- Create: `components/Modules/Chat/VodChatJob/VodChatJob.xml`
- Create: `components/Modules/Chat/VodChatJob/VodChatJob.brs`

**Interfaces:**
- Consumes: `TwitchGraphQLRequest(data)` from `pkg:/components/Tasks/twitch-api-sdk/shared.brs`.
- Produces: 
  - `field videoId` (string, input)
  - `field offsetSeconds` (integer, input)
  - `field currentPosition` (float, input, observed)
  - `field nextCommentObj` (assocarray, output, alwaysNotify=true)
  - `field readyForNextComment` (boolean, input)
  - `field stopRequested` (boolean, input)
  - `field seekRequested` (integer, input)

- [ ] **Step 1: Write GraphQL query `source/graphql/VideoComments_Query.gql`**
Define query fetching `video(id: $videoID) { comments(contentOffsetSeconds: $contentOffsetSeconds, after: $cursor) { edges { cursor node { id contentOffsetSeconds commenter { displayName login } message { fragments { text } userColor } } } pageInfo { hasNextPage } } }`.

- [ ] **Step 2: Create component definition `VodChatJob.xml`**
Declare Task component extending `Task` with interface fields for `videoId`, `currentPosition`, `nextCommentObj`, `readyForNextComment`, `stopRequested`, and `seekRequested`.

- [ ] **Step 3: Implement `VodChatJob.brs`**
Implement fetching loop using `TwitchGraphQLRequest`, maintaining an in-memory queue of comments for the current 60s window, listening to `currentPosition` to emit matching comments to `nextCommentObj` in the schema expected by `onNewCommentObj()`.

- [ ] **Step 4: Verify syntax and lint**
Run `npm run lint` or `npx bsc --createPackage=false` in project root.

---

### Task 2: Integrate `VodChatJob` into `Chat.xml` and `Chat.brs`

**Files:**
- Modify: `components/Modules/Chat/Chat.xml`
- Modify: `components/Modules/Chat/Chat.brs`

**Interfaces:**
- Consumes: `VodChatJob` component created in Task 1.
- Produces:
  - `field videoId` (string, input)
  - `field videoPosition` (float, input)
  - `field isVod` (boolean, input)

- [ ] **Step 1: Update `Chat.xml` interface and children**
Add interface fields `videoId`, `videoPosition`, `isVod` to `Chat.xml`, and instantiate `<VodChatJob id="VodChatJob" control="stop" />`.

- [ ] **Step 2: Update `Chat.brs` to route VOD vs Live**
If `m.top.isVod` is true, observe `VodChatJob.nextCommentObj` instead of `ChatJob` IRC. Forward `m.top.videoPosition` to `VodChatJob.currentPosition`. Ensure `stopJobs()` halts both `ChatJob` and `VodChatJob`.

- [ ] **Step 3: Verify build and compile**
Run `npm run build` to verify SceneGraph bindings and BrightScript syntax.

---

### Task 3: Hook VideoPlayer to Pass VOD Data to Chat

**Files:**
- Modify: `components/Scenes/VideoPlayer/VideoPlayer.brs`

**Interfaces:**
- Consumes: `Chat.isVod`, `Chat.videoId`, `Chat.videoPosition`.

- [ ] **Step 1: Enable `initChat()` for VOD content**
In `VideoPlayer.brs`, update line 359 to allow chat initialization when `isLiveContent` or `contentType = "VOD"`.

- [ ] **Step 2: Pass VOD identity and position**
In `initChat()`, set `m.chatWindow.isVod = (m.top.contentRequested.contentType = "VOD")` and `m.chatWindow.videoId = m.video.video_id`. In `onPositionChanged()`, forward `m.chatWindow.videoPosition = m.video.position`.

- [ ] **Step 3: Handle seek/scrub in player**
When user seeks or resumes VOD, notify chat component of timestamp change.

- [ ] **Step 4: Verify full build**
Run `npm run build` and ensure zero errors or warnings.

---

### Task 4: Package and Deploy to Physical Roku for Verification

**Files:**
- Output: `out/Stitch-Revitalized-For-Roku.zip`

- [ ] **Step 1: Create package zip**
Compile with `npm run package` (or zip bundle).

- [ ] **Step 2: Sideload to Roku at `192.168.1.3`**
Execute deployment via curl with user's developer credentials (`rokudev:2903`).

- [ ] **Step 3: Verification on TV**
Open a VOD on the TV, toggle chat on, and verify comments appear in sync with playback.
