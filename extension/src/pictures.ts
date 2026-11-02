// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

/**
 * The last picture a debug session's frames carried. A running frame whose picture has not changed leaves out its
 * pixels, so a display panel that opens after the picture was sent gets it from here.
 */
export class PictureCache {
    private pixels: string | undefined;

    /** Forgets the picture, as a new session starts. */
    reset(): void { this.pixels = undefined; }

    /**
     * Notes a retro/frame body's picture and returns the body to post: as it is, or with the last picture added
     * when the panel is new and the frame has none.
     */
    frame(body: unknown, newPanel: boolean): unknown {
        if (typeof body !== "object" || body === null || !("video" in body)) return body;
        const video = body.video;
        if (typeof video !== "object" || video === null) return body;
        if ("pixels" in video && typeof video.pixels === "string") {
            this.pixels = video.pixels;
            return body;
        }
        if (!newPanel || this.pixels === undefined) return body;
        return { ...body, video: { ...video, pixels: this.pixels } };
    }
}
