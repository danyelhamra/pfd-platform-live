export class ClubValidationError extends Error {}

export function validateClubFields(body: Record<string, unknown>) {
  const text = (key: string, label: string, max: number, required = true) => {
    const value = body[key] ?? "";
    if (
      typeof value !== "string" ||
      value.trim().length > max ||
      (required && !value.trim())
    ) {
      throw new ClubValidationError(`Enter a valid ${label}.`);
    }
    return value.trim();
  };
  const result = {
    name: text("name", "club name", 120),
    city: text("city", "city", 80),
    state: text("state", "state / province / region", 80),
    country: text("country", "country", 80),
    contact_email: text(
      "contact_email",
      "club email address",
      254,
    ).toLowerCase(),
    contact_number: text("contact_number", "contact number", 32),
    league: text("league", "league / competition", 160),
    sport: text("sport", "sport / club type", 80),
    description: text("description", "description", 2000, false),
  };
  if (!/^\S+@\S+\.\S+$/.test(result.contact_email))
    throw new ClubValidationError("Enter a valid club email address.");
  const digits = result.contact_number.replace(/[^0-9]/g, "");
  if (
    !/^\+?[0-9() .-]+$/.test(result.contact_number) ||
    digits.length < 7 ||
    digits.length > 15
  ) {
    throw new ClubValidationError(
      "Enter a valid contact number containing 7 to 15 digits. Spaces, brackets and a leading + are allowed.",
    );
  }
  return {
    ...result,
    location: [result.city, result.state, result.country].join(", "),
  };
}

export function isCompleteClub(club: Record<string, unknown>) {
  try {
    validateClubFields(club);
    return true;
  } catch {
    return false;
  }
}
