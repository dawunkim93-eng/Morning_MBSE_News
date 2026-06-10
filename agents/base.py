from abc import ABC, abstractmethod


class BaseAgent(ABC):
    @abstractmethod
    def run(self) -> list[dict]:
        pass

    @staticmethod
    def _dedup(items: list[dict]) -> list[dict]:
        seen, result = set(), []
        for item in items:
            if item["title"] not in seen:
                seen.add(item["title"])
                result.append(item)
        return result
