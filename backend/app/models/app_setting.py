from sqlalchemy import Column, String, Text

from ..database import Base


class AppSetting(Base):
    __tablename__ = "app_settings"

    key = Column(String(50), primary_key=True)
    value = Column(Text, nullable=False)

    def to_dict(self):
        return {"key": self.key, "value": self.value}