export interface IGeoLocation {
    city: string;
    state: string;
    country: string;
    countryCode: string;
    postcode: string;
    latitude: number;
    longitude: number;
    /** Horizontal accuracy in metres, -1 if unknown. */
    accuracy: number;
    /** When the fix was taken, ms since epoch. */
    timestamp: number;
    /** false when the user granted only approximate location. Web: always true, browsers do not report it. */
    isPrecise: boolean;
    /** Android: reliable mock-provider flag. iOS: catches Xcode/GPX simulation only. Web: always false. */
    isMock: boolean;
    platform: "android" | "ios" | "web";
}
