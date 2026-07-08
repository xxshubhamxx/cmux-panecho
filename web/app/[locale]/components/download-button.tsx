"use client";

import { Menu } from "@base-ui-components/react/menu";
import { useTranslations } from "next-intl";
import { Link, usePathname } from "../../../i18n/navigation";
import {
  DOWNLOAD_CONFIRMATION_HREF,
  DOWNLOAD_CONFIRMATION_PATH,
  DOWNLOAD_URL,
  WAITLIST_PLATFORMS,
  type WaitlistPlatform,
} from "../../lib/download";
import { ctaButtonStyle } from "./cta-styles";
import { PlatformIcon } from "./platform-icons";
import { WaitlistDialog } from "./waitlist-dialog";

// Per-size pill padding in px. downloadRight = gap LEFT of the divider,
// caretLeft = gap RIGHT of it. Applied as inline styles (not Tailwind classes)
// because the tuned values include odd px like 9/11 that have no spacing token,
// and because arbitrary values like `pr-[9px]` did not reliably resolve on the
// base-ui Menu.Trigger button; inline px renders the exact value in dev + prod.
const PILL_PADDING = {
  default: { downloadLeft: 20, downloadRight: 9, caretLeft: 7, caretRight: 11 },
  sm: { downloadLeft: 12, downloadRight: 7, caretLeft: 5, caretRight: 9 },
} as const;

export function DownloadButton({
  size = "default",
  location = "hero",
  className,
}: {
  size?: "default" | "sm";
  location?: string;
  className?: string;
}) {
  void location;
  const t = useTranslations("common");
  const tp = useTranslations("platforms");
  const tw = useTranslations("waitlist");
  const pathname = usePathname();
  const isSmall = size === "sm";
  const [waitlistPlatform, setWaitlistPlatform] =
    useState<WaitlistPlatform | null>(null);

  // Open the waitlist dialog on the next frame. Selecting a menu item fires
  // inside a pointer gesture; opening the dialog synchronously lets that same
  // gesture's trailing event count as an outside-press and dismiss the dialog
  // the instant it mounts. Deferring past the gesture lets it open and stay.
  const openWaitlist = (platform: WaitlistPlatform) => {
    requestAnimationFrame(() => setWaitlistPlatform(platform));
  };

  // On the confirmation page itself, navigating to the same route is a no-op
  // (the page stays mounted, so its auto-download won't re-fire). Point the CTA
  // straight at the asset there so it still works as a retry; everywhere else
  // it navigates same-tab to the confirmation page (no popup, no new tab).
  const onConfirmationPage = pathname === DOWNLOAD_CONFIRMATION_PATH;
  const className_ = `inline-flex items-center whitespace-nowrap rounded-full font-medium bg-foreground hover:opacity-85 transition-opacity ${
    isSmall ? "gap-2 px-4 py-1.5 text-xs" : "gap-2.5 px-5 py-2.5 text-[15px]"
  } ${className ?? ""}`;
  const style = { color: "var(--background)", textDecoration: "none" } as const;
  // The Apple mark artwork has an 814:1000 aspect ratio. Derive the box width
  // from its height so the glyph fills the frame instead of letterboxing inside
  // an over-wide box, and nudge it onto the label's cap-height midline.
  const logoHeight = isSmall ? 14 : 19;
  const logoWidth = (logoHeight * 814) / 1000;
  const logoNudge = isSmall ? -0.25 : -0.5;
  const macIcon = (
    <svg
      width={logoWidth}
      height={logoHeight}
      viewBox="0 0 814 1000"
      fill="currentColor"
      style={{ transform: `translateY(${logoNudge}px)` }}
      aria-hidden="true"
    >
      <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57.8-155.5-127.4c-58.3-81.6-105.6-208.4-105.6-328.6 0-193 125.6-295.5 249.2-295.5 65.7 0 120.5 43.1 161.7 43.1 39.2 0 100.4-45.8 175.1-45.8 28.3 0 130.3 2.6 197.2 99.2zM554.1 159.4c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.9 32.4-57.2 83.6-57.2 135.4 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 137.6-71.2z" />
    </svg>
  );

  if (onConfirmationPage) {
    return (
      <a href={DOWNLOAD_URL} className={className_} style={style}>
        {icon}
        {t("downloadForMac")}
      </a>
    );
  }

  return (
    <Link
      href={DOWNLOAD_CONFIRMATION_HREF}
      className={className_}
      style={style}
    >
      {icon}
      {t("downloadForMac")}
    </Link>
  );
}
