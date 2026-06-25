module.exports = async function* neotestNodeReporter(source) {
  for await (const event of source) {
    yield `${JSON.stringify(event)}\n`;
  }
};
