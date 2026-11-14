// Open during the click gesture so Safari can keep the private file in a new tab.
export async function openPrivateFile(load: () => Promise<{ url: string }>) {
  const tab = window.open("about:blank", "_blank");
  if (!tab) throw Error("Allow a new tab to open this file, then try again.");
  tab.opener = null;
  try {
    const result = await load();
    tab.location.href = result.url;
  } catch (error) {
    tab.close();
    throw error;
  }
}
